<?php

declare(strict_types=1);

use Drupal\Core\File\FileSystemInterface;
use Drupal\image\Entity\ImageStyle;

$sourceUri = getenv('HC_SOURCE_URI') ?: 'public://infinityui_healthcheck/source.jpg';
$styleName = getenv('HC_STYLE') ?: 'thumbnail';

$errors = [];

$fileSystem = \Drupal::service('file_system');
$fileRepository = \Drupal::service('file.repository');

$publicRoot = $fileSystem->realpath('public://');
$privateRoot = $fileSystem->realpath('private://');
$tempRoot = $fileSystem->realpath('temporary://');

$checkWritable = static function (string|false|null $path, string $label, bool $required = true) use (&$errors): void {
  if ($path === false || $path === null || $path === '') {
    if ($required) {
      $errors[] = "Path not resolvable: {$label}";
    }
    else {
      fwrite(STDOUT, "WARN: Optional path not resolvable: {$label}\n");
    }
    return;
  }
  if (!is_dir($path)) {
    if ($required) {
      $errors[] = "Directory missing: {$label} ({$path})";
    }
    else {
      fwrite(STDOUT, "WARN: Optional directory missing: {$label} ({$path})\n");
    }
    return;
  }
  if (!is_writable($path)) {
    $errors[] = "Directory not writable: {$label} ({$path})";
  }
};

$checkWritable($publicRoot, 'public://');
$checkWritable($privateRoot, 'private://', false);
$checkWritable($tempRoot, 'temporary://');

$sourceDir = dirname($sourceUri);
if (!$fileSystem->prepareDirectory($sourceDir, FileSystemInterface::CREATE_DIRECTORY | FileSystemInterface::MODIFY_PERMISSIONS)) {
  $errors[] = "Unable to prepare source directory: {$sourceDir}";
}

$sourceRealpath = $fileSystem->realpath($sourceUri);
if (!function_exists('imagecreatetruecolor') || !function_exists('imagejpeg')) {
  $errors[] = 'GD image functions are unavailable (imagecreatetruecolor/imagejpeg).';
}
else {
  $imageResource = imagecreatetruecolor(32, 32);
  if ($imageResource === false) {
    $errors[] = 'Failed to create in-memory GD image resource.';
  }
  else {
    $bg = imagecolorallocate($imageResource, 28, 99, 216);
    imagefilledrectangle($imageResource, 0, 0, 31, 31, $bg);

    ob_start();
    imagejpeg($imageResource, null, 90);
    $binary = ob_get_clean();
    imagedestroy($imageResource);

    if (!is_string($binary) || $binary === '') {
      $errors[] = 'Failed to generate JPEG binary from GD image resource.';
    }
  }
}

if (empty($errors)) {
  try {
    $file = $fileRepository->writeData($binary, $sourceUri, FileSystemInterface::EXISTS_REPLACE);
    $file->setPermanent();
    $file->save();
    $sourceRealpath = $fileSystem->realpath($sourceUri);
  }
  catch (\Throwable $exception) {
    $errors[] = 'Failed to create source file: ' . $exception->getMessage();
  }
}

if (empty($errors)) {
  try {
    $image = \Drupal::service('image.factory')->get($sourceUri);
    if (!$image->isValid()) {
      $errors[] = 'Source image is not readable by active Drupal image toolkit.';
    }
  }
  catch (\Throwable $exception) {
    $errors[] = 'Image toolkit validation failed: ' . $exception->getMessage();
  }
}

$imageStyle = ImageStyle::load($styleName);
if (!$imageStyle) {
  $errors[] = "Image style not found: {$styleName}";
}

$derivativeUri = null;
$derivativeRealpath = null;
$createResult = null;
if (empty($errors) && $imageStyle) {
  $derivativeUri = $imageStyle->buildUri($sourceUri);
  $derivativeDir = dirname($derivativeUri);

  if (!$fileSystem->prepareDirectory($derivativeDir, FileSystemInterface::CREATE_DIRECTORY | FileSystemInterface::MODIFY_PERMISSIONS)) {
    $errors[] = "Unable to prepare derivative directory: {$derivativeDir}";
  }
  else {
    try {
      $createResult = $imageStyle->createDerivative($sourceUri, $derivativeUri);
      $derivativeRealpath = $fileSystem->realpath($derivativeUri);
      if ($createResult !== true) {
        fwrite(STDOUT, "WARN: createDerivative() returned non-true for {$derivativeUri}\n");
      }
      if ($derivativeRealpath === false || !file_exists($derivativeRealpath)) {
        fwrite(STDOUT, "WARN: Derivative not present on disk yet (possible lazy generation): {$derivativeUri}\n");
      }
    }
    catch (\Throwable $exception) {
      $errors[] = 'Derivative generation failed: ' . $exception->getMessage();
    }
  }
}

if (!empty($errors)) {
  fwrite(STDERR, "MEDIA_HEALTHCHECK=FAIL\n");
  foreach ($errors as $error) {
    fwrite(STDERR, "ERROR: {$error}\n");
  }
  throw new \RuntimeException('Media healthcheck failed.');
}

fwrite(STDOUT, "MEDIA_HEALTHCHECK=OK\n");
fwrite(STDOUT, "SOURCE_URI={$sourceUri}\n");
fwrite(STDOUT, "SOURCE_REALPATH={$sourceRealpath}\n");
fwrite(STDOUT, "STYLE={$styleName}\n");
fwrite(STDOUT, "DERIVATIVE_URI={$derivativeUri}\n");
fwrite(STDOUT, "DERIVATIVE_REALPATH={$derivativeRealpath}\n");
fwrite(STDOUT, 'DERIVATIVE_CREATE_RESULT=' . var_export($createResult, true) . "\n");
fwrite(STDOUT, 'DERIVATIVE_URL=' . $imageStyle->buildUrl($sourceUri) . "\n");
