export interface Env {
  ATTACHMENTS: R2Bucket;
  CITRATION_ENV?: string;
  DB: D1Database;
  JWT_SIGNING_SECRET?: string;
}
