export function uniqueUserNames(names) {
  const seen = new Set();
  return names.filter((name) => {
    if (seen.has(name)) return false;
    seen.add(name);
    return true;
  });
}
