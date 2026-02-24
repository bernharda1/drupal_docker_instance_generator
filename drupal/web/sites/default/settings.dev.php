<?php

declare(strict_types=1);

$config['system.logging']['error_level'] = 'verbose';
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;
$settings['skip_permissions_hardening'] = TRUE;

$settings['container_yamls'][] = $app_root . '/sites/development.services.yml';
$settings['container_yamls'][] = $app_root . '/' . $site_path . '/services.local.yml';

if (empty($settings['trusted_host_patterns'])) {
  $settings['trusted_host_patterns'] = ['^localhost$', '^127\\.0\\.0\\.1$'];
}
