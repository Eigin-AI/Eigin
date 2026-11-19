import type { User } from "./lib/server/auth.ts";
declare global {
  namespace App {
    interface Locals {
      user: User | null;
    }
  }
}
export {};
