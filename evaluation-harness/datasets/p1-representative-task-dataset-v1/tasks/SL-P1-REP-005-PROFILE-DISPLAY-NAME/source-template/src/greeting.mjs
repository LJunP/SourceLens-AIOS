import { formatDisplayName } from "./profile.mjs";

export function greeting(profile) {
  return `Hello, ${formatDisplayName(profile)}!`;
}
