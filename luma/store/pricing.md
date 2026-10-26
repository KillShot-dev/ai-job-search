# Pricing and the $1,000 / month target

The business target is paid-download revenue above $1,000 in a month. That is a target, not a forecast and not a promise. Nothing in the competitor note shows that a new pack reaches it.

## Fee used in the arithmetic

Play Console Help, “Service fees”, retrieved Oct 25, 2026 PT:

https://support.google.com/googleplay/android-developer/answer/112622?hl=en

For buyers in the United States (rollout date on that page: June 30, 2026), the first $1M of annual earnings is listed as **10% plus a 5% billing fee**, across subscriptions and other transactions. The footnote says the billing fee applies to the initial purchase of a paid app. Combined, that is **15%**. Developer proceeds in this band are **85%** of the price before tax.

Above that first $1M, the “Standard” row on the same table lists other transactions from new installs at **20% plus a 5% billing fee** (25% combined), so proceeds would be 75%. A new icon pack is inside the first band until lifetime-year revenue passes $1M.

Tax, currency conversion, refunds, and the subscriber/install “new vs existing” split are not in the arithmetic below. The help page is the source for the percentages. The division is just division.

## Sales that would clear $1,000 in a month

At 15% combined fee, net is price × 0.85. Sales needed are `ceil(1000 / net)`.

| List price | Net at 15% | Sales for $1,000 |
| --- | ---: | ---: |
| $1.99 | $1.69 | 592 |
| $2.49 | $2.12 | 473 |
| $2.99 | $2.54 | 394 |
| $3.49 | $2.97 | 338 |

At a 25% combined fee, a $2.99 sale nets $2.24, and the same $1,000 takes 446 sales.

## What the paid competitors imply

They do not imply a monthly sales rate.

- LineX and Pixels show 100,000+ lifetime installs at $0.79 and $0.99. Spread over the years those packs have been updated, that bracket can be far below 394 sales in a single month, or above it. The bracket cannot say which.
- Outline shows 50,000+ lifetime installs at $2.49.
- Lena shows 10,000+ at $3.49.
- Ares Light shows 1,000+ lifetime installs and 89 ratings at $3.49. That is a small audience for a pack in the same price area as a $2.99–$3.49 Luma.

A $2.99 price matches a “premium, fewer buyers” position. It does not match the evidence that several hundred people will pay it every month. Reaching the target means outselling the visible popularity of Ares Light by a wide margin and holding a pace that the public install brackets do not prove.

## Recommendation

Use **$2.99** only for a finished pack: 300 original chart icons, tested mappings, screenshots from a real launcher. Keep the prototype off the store. If early closed-test demand is thin, $1.99 lowers the net and raises the sales count required (592 at a 15% fee). Dropping to $0.99 to match LineX abandons the premium position and still needs 1,189 sales a month at a 15% fee to clear $1,000 (`ceil(1000 / (0.99 × 0.85))`). The sales counts in the table use that unrounded net. The dollar column is rounded to the cent.

Revisit the fee table in Play Console Help on the day of submission. The US schedule on the page retrieved for this note is not a permanent contract.
