/**
 * MoveClaw contract addresses and ABIs
 * Deployed on Movement Testnet (Bardock)
 */

// Contract module address (deployer address)
export const MOVECLAW_MODULE_ADDRESS =
  "0xa408be510aeaa755b9fc670385022be50573b37434d16d9b1f5300d5ed3c2174";

// Full function identifiers
export const MOVECLAW_MESSAGE = {
  module: `${MOVECLAW_MODULE_ADDRESS}::message`,
  setMessage: `${MOVECLAW_MODULE_ADDRESS}::message::set_message`,
  getMessage: `${MOVECLAW_MODULE_ADDRESS}::message::get_message`,
  messageExists: `${MOVECLAW_MODULE_ADDRESS}::message::message_exists`,
} as const;
