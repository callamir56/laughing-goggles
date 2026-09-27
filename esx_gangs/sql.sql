CREATE TABLE IF NOT EXISTS `gangs` (
    `name` VARCHAR(50) NOT NULL,
    `label` VARCHAR(80) NOT NULL,
    `parking` LONGTEXT NULL,
    `spawn` LONGTEXT NULL,
    `stash` LONGTEXT NULL,
    `wardrobe` LONGTEXT NULL,
    `boss` LONGTEXT NULL,
    `money` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `renew_days` INT NOT NULL DEFAULT 30,
    `expires_at` INT NULL DEFAULT NULL,
    `active` TINYINT NOT NULL DEFAULT 1,
    PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_ranks` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `gang` VARCHAR(50) NOT NULL,
    `grade` INT NOT NULL,
    `label` VARCHAR(80) NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `gang_grade` (`gang`, `grade`),
    CONSTRAINT `fk_gang_ranks` FOREIGN KEY (`gang`) REFERENCES `gangs` (`name`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_vehicles` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `gang` VARCHAR(50) NOT NULL,
    `model` VARCHAR(60) NOT NULL,
    `label` VARCHAR(80) NOT NULL,
    `props` LONGTEXT NULL,
    `stored` TINYINT NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE KEY `gang_model` (`gang`, `model`),
    CONSTRAINT `fk_gang_vehicles` FOREIGN KEY (`gang`) REFERENCES `gangs` (`name`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_stash_logs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `gang` VARCHAR(50) NOT NULL,
    `identifier` VARCHAR(80) NOT NULL,
    `player` VARCHAR(80) NOT NULL,
    `action` VARCHAR(20) NOT NULL,
    `item` VARCHAR(80) NOT NULL,
    `count` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `gang_time` (`gang`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `users`
    ADD COLUMN IF NOT EXISTS `gang` VARCHAR(50) NULL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `gang_grade` INT NULL DEFAULT 0;

ALTER TABLE `gang_vehicles`
    ADD COLUMN IF NOT EXISTS `props` LONGTEXT NULL,
    ADD COLUMN IF NOT EXISTS `stored` TINYINT NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS `gang_outfits` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `gang` VARCHAR(50) NOT NULL,
    `kind` VARCHAR(20) NOT NULL,
    `grade` INT NULL DEFAULT NULL,
    `skin` LONGTEXT NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `gang_kind_grade` (`gang`, `kind`, `grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_player_skins` (
    `identifier` VARCHAR(80) NOT NULL,
    `skin` LONGTEXT NOT NULL,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_relations` (
    `gang_source` VARCHAR(50) NOT NULL,
    `gang_target` VARCHAR(50) NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'neutral',
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`gang_source`,`gang_target`),
    KEY `target_idx` (`gang_target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_chats` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `gang_from` VARCHAR(50) NOT NULL,
    `gang_to` VARCHAR(50) NOT NULL,
    `sender_identifier` VARCHAR(80) NOT NULL,
    `sender_name` VARCHAR(80) NOT NULL,
    `sender_gang` VARCHAR(50) NOT NULL,
    `message` TEXT NOT NULL,
    `type` VARCHAR(20) NOT NULL DEFAULT 'text',
    `extra` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `chat_pair` (`gang_from`,`gang_to`,`created_at`),
    KEY `chat_pair2` (`gang_to`,`gang_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `gang_chats`
    ADD COLUMN IF NOT EXISTS `type` VARCHAR(20) NOT NULL DEFAULT 'text',
    ADD COLUMN IF NOT EXISTS `extra` LONGTEXT NULL;

ALTER TABLE `gangs`
    ADD COLUMN IF NOT EXISTS `craft` LONGTEXT NULL,
    ADD COLUMN IF NOT EXISTS `access` LONGTEXT NULL,
    ADD COLUMN IF NOT EXISTS `recipes` LONGTEXT NULL;

ALTER TABLE `gang_vehicles`
    ADD COLUMN IF NOT EXISTS `impounded` TINYINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `last_used` INT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `gang_members` (
    `identifier` VARCHAR(80) NOT NULL,
    `gang` VARCHAR(50) NOT NULL,
    `grade` INT NOT NULL DEFAULT 0,
    `name` VARCHAR(80) NOT NULL DEFAULT '',
    PRIMARY KEY (`identifier`),
    KEY `gang_idx` (`gang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_groups` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(50) NOT NULL,
    `label` VARCHAR(80) NOT NULL,
    `creator_gang` VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_group_members` (
    `group_id` INT NOT NULL,
    `gang_name` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`group_id`, `gang_name`),
    KEY `gang_idx` (`gang_name`),
    CONSTRAINT `fk_group` FOREIGN KEY (`group_id`) REFERENCES `gang_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_group_chats` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `group_id` INT NOT NULL,
    `sender_identifier` VARCHAR(80) NOT NULL,
    `sender_name` VARCHAR(80) NOT NULL,
    `sender_gang` VARCHAR(50) NOT NULL,
    `message` TEXT NOT NULL,
    `type` VARCHAR(20) NOT NULL DEFAULT 'text',
    `extra` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `group_time` (`group_id`, `created_at`),
    CONSTRAINT `fk_group_chat` FOREIGN KEY (`group_id`) REFERENCES `gang_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gang_blocks` (
    `blocker_gang` VARCHAR(50) NOT NULL,
    `blocked_gang` VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`blocker_gang`, `blocked_gang`),
    KEY `blocked_idx` (`blocked_gang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ================== سیستم تمدید / انقضای گنگ ==================
-- برای دیتابیس‌های قدیمی (اگه جدول gangs از قبل وجود داره)
ALTER TABLE `gangs`
    ADD COLUMN IF NOT EXISTS `renew_days` INT NOT NULL DEFAULT 30,
    ADD COLUMN IF NOT EXISTS `expires_at` INT NULL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `active` TINYINT NOT NULL DEFAULT 1;
