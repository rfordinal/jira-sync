-- tasks

CREATE TABLE `tasks` (
  `id_customer` varchar(10) COLLATE utf8_bin DEFAULT NULL,
  `id_vendor` varchar(10) COLLATE utf8_bin DEFAULT NULL,
  `updated_customer` datetime DEFAULT NULL,
  `updated_vendor` datetime DEFAULT NULL,
  `data_customer` longblob,
  `data_vendor` longblob,
  UNIQUE KEY `id_vendor_UNIQUE` (`id_vendor`),
  UNIQUE KEY `id_customer_UNIQUE` (`id_customer`),
  UNIQUE KEY `unique` (`id_customer`,`id_vendor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

-- attachments

CREATE TABLE `attachments` (
  `issue_vendor` varchar(10) COLLATE utf8_bin NOT NULL,
  `issue_customer` varchar(10) COLLATE utf8_bin NOT NULL,
  `filename` varchar(128) COLLATE utf8_bin NOT NULL,
  UNIQUE KEY `unique` (`issue_vendor`,`filename`,`issue_customer`),
  UNIQUE KEY `customer` (`issue_customer`,`filename`),
  UNIQUE KEY `vendor` (`issue_vendor`,`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

-- comments

CREATE TABLE `comments` (
  `id_customer` int(11) DEFAULT NULL,
  `id_vendor` int(11) DEFAULT NULL,
  `updated_customer` datetime DEFAULT NULL,
  `updated_vendor` datetime DEFAULT NULL,
  UNIQUE KEY `unique` (`id_customer`,`id_vendor`) USING BTREE,
  UNIQUE KEY `id_customer_UNIQUE` (`id_customer`),
  UNIQUE KEY `id_vendor_UNIQUE` (`id_vendor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

