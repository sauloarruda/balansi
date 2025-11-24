-- CreateTable
CREATE TABLE IF NOT EXISTS "users" (
  "id" SERIAL NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "email" VARCHAR(255) NOT NULL,
  "temporary_password" VARCHAR(255),
  "cognito_id" VARCHAR(255),
  "status" VARCHAR(50) NOT NULL DEFAULT 'pending_confirmation',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);
-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "users_email_key" ON "users"("email");
