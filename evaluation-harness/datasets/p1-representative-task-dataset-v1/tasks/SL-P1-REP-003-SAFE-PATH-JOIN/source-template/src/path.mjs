import { resolve } from "node:path";

export function resolveUnder(root, candidate) {
  return resolve(root, candidate);
}
