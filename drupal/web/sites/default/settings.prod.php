<?php

declare(strict_types=1);

$config['system.logging']['error_level'] = 'hide';
$config['system.performance']['css']['preprocess'] = TRUE;
$config['system.performance']['js']['preprocess'] = TRUE;

$settings['container_yamls'][] = $app_root . '/sites/production.services.yml';
