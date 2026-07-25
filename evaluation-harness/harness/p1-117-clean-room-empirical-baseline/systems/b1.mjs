import {
  buildExactRequest,
} from "./common.mjs";

export const SYSTEM_ID = "B1";

export function buildProviderRequest({
  entry,
  configuration,
  disclosure,
  responseSchemaIdentity,
}) {
  return buildExactRequest({
    entry,
    configuration,
    disclosure,
    responseSchemaIdentity,
  });
}
