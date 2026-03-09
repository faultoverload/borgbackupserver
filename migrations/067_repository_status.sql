-- Add status tracking to repositories table
-- Migration: 067_repository_status.sql

ALTER TABLE repositories
ADD COLUMN status ENUM('ok', 'warning', 'error') NOT NULL DEFAULT 'ok',
ADD COLUMN status_message VARCHAR(255) DEFAULT NULL,
ADD COLUMN last_checked_at DATETIME DEFAULT NULL;
