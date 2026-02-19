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

// Prediction Market function identifiers
export const MOVECLAW_PREDICTION_MARKET = {
  module: `${MOVECLAW_MODULE_ADDRESS}::prediction_market`,
  initRegistry: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::init_registry`,
  createMarket: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::create_market`,
  placeBet: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::place_bet`,
  resolveMarket: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::resolve_market`,
  claimWinnings: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::claim_winnings`,
  getMarket: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::get_market`,
  getPosition: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::get_position`,
  getNextMarketId: `${MOVECLAW_MODULE_ADDRESS}::prediction_market::get_next_market_id`,
} as const;
