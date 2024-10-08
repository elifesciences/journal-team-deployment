<?php
return [
    'debug' => ${search_app_debug_flag:-false},
    'validate' => false,
    'ttl' => 300,
    'elastic_servers' => ['https://opensearch:9200'],
    'elastic_username' => 'admin',
    'elastic_password' => 'admin',
    'elastic_ssl_verification' => false,
    'elastic_logging' => true,
    'elastic_force_sync' => false,
    'api_url' => '${api_url}',
    'api_requests_batch' => 20,
    'rate_limit_minimum_page' => 21,
    'logger.level' => '${search_app_logger_level:-info}',
    'aws' => [
        'queue_name' => '${search_queue_name}',
        'credential_file' => true,
        'region' => '${aws_region}',
    ],
    'rds_articles' => [
        '30274' => [
            'date' => '2020-08-24T13:30:00Z',
            'display' => 'https://elife.stencila.io/article-30274/',
            'download' => 'https://hub.stenci.la/api/projects/518/snapshots/15/archive',
        ],
        '43154' => [
            'date' => '2020-10-22T10:30:00Z',
            'display' => 'https://elife.stencila.io/article-43154/v26/',
            'download' => 'https://hub.stenci.la/api/projects/588/snapshots/26/archive',
        ],
        '52258' => [
            'date' => '2020-08-24T13:30:00Z',
            'display' => 'https://elife.stencila.io/article-52258/',
            'download' => 'https://hub.stenci.la/api/projects/583/snapshots/13/archive',
        ],
        '55650' => [
            'date' => '2021-03-24T11:00:00Z',
            'display' => 'https://elife.stencila.io/article-55650/v29/',
            'download' => 'https://hub.stenci.la/api/projects/1309/snapshots/29/archive',
        ],
        '57067' => [
            'date' => '2020-11-03T10:00:00Z',
            'display' => 'https://elife.stencila.io/article-57067/v6/',
            'download' => 'https://hub.stenci.la/api/projects/1281/snapshots/6/archive',
        ],
        '60287' => [
            'date' => '2021-02-05T11:00:00Z',
            'display' => 'https://elife.stencila.io/article-60287/v9/',
            'download' => 'https://hub.stenci.la/api/projects/1307/snapshots/9/archive',
        ],
        '61277' => [
            'date' => '2021-08-31T13:00:00Z',
            'display' => 'https://elife.stencila.io/article-61277/v71/',
            'download' => 'https://hub.stenci.la/api/projects/1342/snapshots/71/archive',
        ],
        '61523' => [
            'date' => '2020-12-08T11:00:00Z',
            'display' => 'https://elife.stencila.io/article-61523/v14/',
            'download' => 'https://hub.stenci.la/api/projects/1316/snapshots/14/archive',
        ],
        '65658' => [
            'date' => '2021-06-01T13:00:00Z',
            'display' => 'https://elife.stencila.io/article-65658/v23/',
            'download' => 'https://hub.stenci.la/api/projects/1469/snapshots/23/archive',
        ],
        '67460' => [
            'date' => '2021-10-18T13:00:00Z',
            'display' => 'https://elife.stencila.io/article-67460/v27/',
            'download' => 'https://hub.stenci.la/api/projects/1511/snapshots/27/archive',
        ],
        '72666' => [
            'date' => '2022-04-12T13:00:00Z',
            'display' => 'https://elife.stencila.io/article-72666/v10/',
            'download' => 'https://hub.stenci.la/api/projects/1649/snapshots/10/archive',
        ],
        '76559' => [
            'date' => '2022-03-24T16:00:00Z',
            'display' => 'https://elife.stencila.io/article-76559/v12/',
            'download' => 'https://hub.stenci.la/api/projects/1647/snapshots/12/archive',
        ],
    ],
    'reviewed_preprints' => [],
];
