import { readFileSync } from "node:fs";

import {
  assert,
  canonicalJson,
  exactKeys,
  fail,
} from "./core.mjs";

const PROFILE_MARKER = /<!-- BEGIN (FOUNDER_[A-Z0-9_]*PROFILE_JSON) -->\s*```json\s*([\s\S]*?)\s*```\s*<!-- END \1 -->/g;
const TASK_DECLARATION = /Task ID：`(AIOS-P1-[0-9]{3}_[A-Z0-9_]+)`/g;

export function parsePacketTaskProfiles(packetPath) {
  const text = readFileSync(packetPath, "utf8");
  const taskIds = [...text.matchAll(TASK_DECLARATION)].map((match) => match[1]);
  const matches = [...text.matchAll(PROFILE_MARKER)];
  const markers = matches.map((match) => match[1]);
  assert(taskIds.length > 0, "TASK_SET_EMPTY", "packet declares no route Tasks");
  assert(new Set(taskIds).size === taskIds.length, "TASK_ID_DUPLICATE", "packet Task IDs are duplicated");
  assert(matches.length > 0, "PROFILE_SET_EMPTY", "packet contains no exact Founder profiles");
  assert(new Set(markers).size === markers.length, "PROFILE_MARKER_DUPLICATE", "profile markers are duplicated");
  const profiles = matches.map((match) => {
    try {
      return JSON.parse(match[2]);
    } catch (error) {
      fail("PROFILE_JSON_INVALID", `profile ${match[1]} JSON is invalid: ${error.message}`);
    }
  });
  return { taskIds, profiles, markers };
}

function validateProfileHeader(profile, routeId, label) {
  assert(profile && typeof profile === "object" && !Array.isArray(profile),
    "PROFILE_INVALID", `${label} must be an object`);
  for (const key of ["schema_version", "profile_id", "route_id", "task_id", "external_effects"]) {
    assert(Object.hasOwn(profile, key), "PROFILE_INVALID", `${label}.${key} missing`);
  }
  assert(profile.schema_version === "2.0", "PROFILE_SCHEMA_INVALID", `${label} schema drifted`);
  assert(
    typeof profile.profile_id === "string" && profile.profile_id.length > 0,
    "PROFILE_ID_INVALID",
    `${label} profile id invalid`,
  );
  assert(profile.route_id === routeId, "PROFILE_ROUTE_DRIFT", `${label} route id drifted`);
  exactKeys(
    profile.external_effects,
    ["network", "provider", "secret", "remote", "production", "public"],
    "PROFILE_EFFECTS_INVALID",
    `${label}.external_effects`,
  );
}

export function validateClosedProfileSet({
  routeId,
  taskIds,
  profiles,
  activeTaskId,
  activeProfile = undefined,
}) {
  assert(
    Array.isArray(taskIds) && taskIds.length > 0 && taskIds.every((id) => typeof id === "string"),
    "TASK_SET_INVALID",
    "Task set must be a non-empty string sequence",
  );
  assert(new Set(taskIds).size === taskIds.length, "TASK_ID_DUPLICATE", "Task IDs are duplicated");
  assert(Array.isArray(profiles), "PROFILE_SET_INVALID", "profile set must be a sequence");
  assert(profiles.length === taskIds.length, "PROFILE_SET_NOT_CLOSED",
    "profile count does not equal Task count");
  profiles.forEach((profile, index) => validateProfileHeader(profile, routeId, `profile[${index}]`));
  const profileIds = profiles.map((profile) => profile.profile_id);
  const profileTaskIds = profiles.map((profile) => profile.task_id);
  assert(new Set(profileIds).size === profileIds.length, "PROFILE_ID_DUPLICATE", "profile IDs are duplicated");
  assert(
    profileTaskIds.every((id) => taskIds.includes(id)),
    "PROFILE_TASK_UNKNOWN",
    "profile references an unknown Task",
  );
  assert(
    canonicalJson(profileTaskIds) === canonicalJson(taskIds),
    "PROFILE_TASK_ORDER_DRIFT",
    "profile Task order differs from the declared Task order",
  );
  assert(taskIds.includes(activeTaskId), "ACTIVE_TASK_UNKNOWN", "active Task is not declared");
  const selected = profiles.find((profile) => profile.task_id === activeTaskId);
  assert(selected, "ACTIVE_PROFILE_MISSING", "active Task has no exact Founder profile");
  if (activeProfile !== undefined) {
    assert(activeProfile !== null, "ACTIVE_PROFILE_MISSING",
      "active Contract/authority profile is missing");
    assert(
      canonicalJson(activeProfile) === canonicalJson(selected),
      "ACTIVE_PROFILE_MISMATCH",
      "active Contract/authority profile differs from the exact route profile",
    );
  }
  const routeEffects = canonicalJson(profiles[0].external_effects);
  assert(
    profiles.every((profile) => canonicalJson(profile.external_effects) === routeEffects),
    "PROFILE_EFFECTS_DRIFT",
    "route profiles do not share one external-effect ceiling",
  );
  return {
    route_id: routeId,
    task_ids: [...taskIds],
    profile_ids: profileIds,
    profile_task_ids: profileTaskIds,
    active_task_id: activeTaskId,
    active_profile_id: selected.profile_id,
    closed: true,
  };
}
