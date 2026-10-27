// FileRadar site configuration — EDIT THESE VALUES AT LAUNCH.
// ------------------------------------------------------------------
// TODO (before launch): set LAUNCH_DATE to the real launch date in
// ISO format (YYYY-MM-DD), e.g. "2027-01-15". Until then it stays
// null, and the pricing section honestly states that the launch
// window has not started yet instead of inventing a countdown.
// TODO (before launch): replace DOMAIN_PLACEHOLDER with the real
// domain once it is registered. No made-up live URL is used anywhere
// on this site; all links are relative until then.
// TODO (before launch): wire the Buy button to the licensing
// backend's Stripe Checkout session endpoint (test mode during
// development, live keys only at launch, handled by the backend —
// never by this static page). Until then the Buy button shows an
// honest "not yet available" notice and takes no payment.
// ------------------------------------------------------------------
window.FileRadarConfig = {
  // Placeholder: no launch date has been announced yet.
  LAUNCH_DATE: null, // e.g. "2027-01-15" once announced
  LAUNCH_PRICE_USD: 8,
  LAUNCH_WINDOW_DAYS: 60,
  REGULAR_PRICE_USD: 19,
  LICENSE_MACS: 1,
  DOMAIN_PLACEHOLDER: "TODO: set real domain after registration",
  SUPPORT_EMAIL: "support@metaphasic.net",
  COMPANY: "metaPhasic Group"
};
