<?php

declare(strict_types=1);

$config['system.logging']['error_level'] = 'some';

if (empty($settings['trusted_host_patterns'])) {
  $settings['trusted_host_patterns'] = ['^localhost$', '^127\\.0\\.0\\.1$'];
}
