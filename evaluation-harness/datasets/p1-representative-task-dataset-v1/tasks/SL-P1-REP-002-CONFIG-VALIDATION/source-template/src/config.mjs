const REQUIRED_KEYS = ["mode"];
const ALLOWED_KEYS = new Set(["mode"]);

export function validateConfig(config) {
  for (const key of REQUIRED_KEYS) {
    if (!(key in config)) throw new Error(`missing key: ${key}`);
  }
  return { ok: true, mode: config.mode };
}
