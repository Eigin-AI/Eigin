ALTER TABLE oauth_attempts ADD COLUMN return_to text NOT NULL DEFAULT '/account';
