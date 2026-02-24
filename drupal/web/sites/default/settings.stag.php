<?php

declare(strict_types=1);

$config['system.logging']['error_level'] = 'some';
$config['system.performance']['css']['preprocess'] = TRUE;
$config['system.performance']['js']['preprocess'] = TRUE;

$settings['container_yamls'][] = $app_root . '/sites/staging.services.yml';

if (empty($settings['trusted_host_patterns'])) {
  $settings['trusted_host_patterns'] = ['^localhost$', '^127\\.0\\.0\\.1$'];
}
