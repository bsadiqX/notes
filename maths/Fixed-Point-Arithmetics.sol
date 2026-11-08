/* ── FIXED-POINT ARITHMETIC IN SOLIDITY ───────────────────────────────
 *
 * Solidity does not support native decimal arithmetic for uint256.
 * For example, a uint256 cannot directly store 2.5.
 *
 * Financial protocols therefore represent decimal values as integers by
 * multiplying them by a chosen scaling factor.
 *
 * Example, using a precision of 1e18:
 *
 *     2.5 * 1e18 = 2500000000000000000
 *
 * The choice of precision is a design decision. Therefore,
 * a protocol may use 1e6, 1e8, 1e18, or another scale.
 *
 * Moving forward, it is important to note the following rules, as we will be
 * reflecting much on them:
 *
 * 1. SCALING
 *
 *    Multiply a decimal value by its chosen precision to represent
 *    it as an integer.
 *
 * 2. MULTIPLICATION
 *
 *    When multiplying two scaled values, their scaling factors
 *    multiply as well.
 *
 *        (A * 1e18) * (B * 1e18)
 *        = (A * B) * 1e36
 *
 * 3. RESCALING
 *
 *    To return the product to 18-decimal precision, divide by 1e18.
 *
 *        (A * B * 1e36) / 1e18
 *        = (A * B) * 1e18
 *
 * 4. DIVISION
 *
 *    When dividing two equally scaled values, their scaling factors
 *    cancel.
 *
 *        (A * 1e18) / (B * 1e18)
 *        = A / B
 *
 *    The result is now an ordinary integer ratio, not an 18-decimal
 *    fixed-point result.
 *
 *    To preserve 18-decimal precision, multiply the numerator by 1e18
 *    before dividing:
 *
 *        ((A * 1e18) * 1e18) / (B * 1e18)
 *        = (A / B) * 1e18
 *
 *    We will use these rules to understand the accounting and
 *    mathematical operations throughout Cyfrin__DSCEngine and
 *    other DeFi protocols.
 */


/* ── 1. Cyfrin__DSCEngine, CALCULATING USD VALUE OF COLLATERAL ──────────────────────────
 *
 * Function:
 *
 *     _getUsdValue(address token, uint256 amount)
 *
 * This function calculates the USD value of a given collateral amount.
 *
 * The basic financial relationship is:
 *
 *     USD Value = Token Amount * USD Price per Token
 *
 * Example:
 *
 *     2 ETH * $2,000 = $4,000
 * 
 * However, as explained in above, we must account for the scaling factors when 
 * performing these calculations.
 *
 * Assume:
 *
 *     Token amount = 2 ETH
 *     Token amount in wei = 2e18
 *
 *     ETH price = $2,000
 *     Chainlink price representation = 2000e8
 *
 * STEP 1 — GET THE PRICE FEED
 *
 *     AggregatorV3Interface priceFeed =
 *         AggregatorV3Interface(s_priceFeeds[token]);
 *
 * Retrieves the configured Chainlink price feed address for the
 * collateral token and casts it to the Chainlink interface.
 *
 * STEP 2 — READ THE LATEST PRICE
 *
 *     (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
 *
 * Retrieves the latest price from the feed.
 *
 * The returned price is an int256 and uses the feed's configured
 * decimal precision. In this example, the price uses 8 decimals.
 *
 * STEP 3 — CONVERT THE PRICE TO uint256
 *
 *     uint256 priceUint256 = uint256(price);
 *
 * Converts the signed price into an unsigned integer so it can
 * participate in the subsequent arithmetic.
 *
 * This conversion relies on the expectation that the supported
 * Chainlink price feed returns a positive price.
 *
 * STEP 4 — SCALE THE PRICE
 *
 *     priceUint256 * ADDITIONAL_FEED_PRECISION
 *
 * The constants are:
 *
 *     ADDITIONAL_FEED_PRECISION = 1e10
 *     FEED_PRECISION            = 1e8
 *
 * Remember our scaling rule:
 *
 * We multiply a decimal value by its chosen scaling factor to
 * represent it as an integer.
 *
 * The Chainlink price currently has 8 decimals. Multiplying it
 * by 1e10 converts its representation to 18 decimals.
 *
 *     2000e8 * 1e10 = 2000e18
 *
 * This matches the engine's chosen 1e18 precision convention.
 *
 * STEP 5 — MULTIPLY PRICE BY TOKEN AMOUNT
 *
 *     (priceUint256 * ADDITIONAL_FEED_PRECISION) * amount
 *
 * Remember our multiplication rule:
 *
 * When multiplying two scaled values, their scaling factors
 * multiply as well.
 *
 *     2000e18 * 2e18 = 4000e36
 *
 * The product now carries 36 decimal places.
 *
 * STEP 6 — RESCALE THE RESULT
 *
 *     ((priceUint256 * ADDITIONAL_FEED_PRECISION) * amount)
 *         / PRECISION
 *
 * Remember our rescaling rule:
 *
 * We divide by 1e18 to bring the product back to 18-decimal
 * precision.
 *
 *     4000e36 / 1e18 = 4000e18
 *
 * FINAL RESULT:
 *
 *     4000e18
 *
 * Represents $4,000 using 18 decimal places.
 * 
 * SECURITY:
 *    This implementation assumes collateral amounts use 18 decimals.
 *    That works for WETH, but WBTC on Ethereum uses 8 decimals.
 *
 *    The function does not read the collateral token's decimals or
 *    normalize its amount. Consequently, its USD calculation can be
 *    incorrect for tokens with a different decimal precision.
 */


/* ── 2. Cyfrin__DSCEngine, CALCULATING TOKEN AMOUNT FROM USD VALUE ──────────────────────
 *
 * Function:
 *
 *     getTokenAmountFromUsd(address token, uint256 usdAmountInWei)
 *
 * This function performs the reverse conversion: it calculates
 * how many collateral tokens correspond to a given USD value.
 *
 * The basic financial relationship is:
 *
 *     Token Amount = USD Value / USD Price per Token
 *
 * Example:
 *
 *     USD Value = $100
 *     ETH Price = $2,000
 *
 *     $100 / $2,000 = 0.05 ETH
 *
 * Assume:
 *
 *     USD amount = 100e18
 *     Chainlink ETH price = 2000e8
 *
 * STEP 1 — GET THE PRICE FEED
 *
 *     AggregatorV3Interface priceFeed =
 *         AggregatorV3Interface(s_priceFeeds[token]);
 *
 * Retrieves the configured price feed for the token.
 *
 * STEP 2 — READ THE LATEST PRICE
 *
 *     (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
 *
 * Reads the latest price from the Chainlink feed.
 *
 * STEP 3 — CONVERT THE PRICE TO uint256
 *
 *     uint256 priceUint256 = uint256(price);
 *
 * Converts the signed price into an unsigned integer.
 *
 * STEP 4 — SCALE THE USD AMOUNT BEFORE DIVISION
 *
 *     usdAmountInWei * PRECISION
 *
 * Remember our fixed-point division rule:
 *
 * When dividing two equally scaled values, their scaling factors
 * cancel. To preserve 18-decimal precision in the result, we
 * multiply the numerator by 1e18 before division.
 *
 *     100e18 * 1e18 = 100e36
 *
 * STEP 5 — SCALE THE TOKEN PRICE
 *
 *     priceUint256 * ADDITIONAL_FEED_PRECISION
 *
 * The Chainlink price has 8 decimals. Multiplying by 1e10
 * converts it to the engine's 18-decimal precision convention.
 *
 *     2000e8 * 1e10 = 2000e18
 *
 * STEP 6 — DIVIDE TO GET THE TOKEN AMOUNT
 *
 *     (usdAmountInWei * PRECISION) /
 *     (priceUint256 * ADDITIONAL_FEED_PRECISION)
 *
 * Remember our fixed-point division rule:
 *
 * The numerator now has 36 decimal places, while the denominator
 * has 18 decimal places.
 *
 * Dividing cancels 18 of the numerator's decimal places, leaving
 * an 18-decimal result.
 *
 *     100e36 / 2000e18 = 0.05e18
 *
 * FINAL RESULT:
 *
 *     50000000000000000
 *
 * Represents 0.05 ETH in wei.
 */


/* ── 3. Cyfrin__DSCEngine CALCULATING THE HEALTH FACTOR ───────────────────────────────────
 *
 * The health factor measures the relationship between the value of
 * collateral and the amount of DSC minted.
 *
 * The calculation has two stages:
 *
 * 1. Apply the liquidation threshold to the collateral value.
 * 2. Divide the adjusted collateral value by the DSC debt.
 *
 * The mathematical relationship is:
 *
 *     Health Factor =
 *         (Collateral Value * Liquidation Threshold)
 *         / (Liquidation Precision * DSC Minted)
 *
 * Assume:
 *
 *     Collateral Value = $10,000
 *     DSC Minted       = $3,000
 *
 *     LIQUIDATION_THRESHOLD  = 50
 *     LIQUIDATION_PRECISION  = 100
 *     PRECISION              = 1e18
 *
 * STEP 1 — HANDLE ZERO DSC DEBT
 *
 *     if (totalDscMinted == 0) return type(uint256).max;
 *
 * If the DSC debt is zero, the final calculation would attempt
 * to divide by zero.
 *
 * Instead, the function returns the maximum uint256 value.
 *
 * Mathematically, a positive collateral value divided by zero
 * is undefined. The maximum integer is a computational convention
 * used here to represent an account with no DSC debt.
 *
 * STEP 2 — APPLY THE LIQUIDATION THRESHOLD ─────────────────────────
 *
 *     uint256 collateralAdjustedForThreshold =
 *         (collateralValueInUsd * LIQUIDATION_THRESHOLD)
 *         / LIQUIDATION_PRECISION;
 *
 * This calculates the percentage of collateral value that will
 * be considered in the health factor calculation.
 *
 * The threshold is 50, while the precision is 100.
 *
 * Therefore:
 *
 *     50 / 100 = 0.5 = 50%
 *
 * Using our example, assume the collateral value is $10,000.
 *
 * Remember that `collateralValueInUsd` is already represented
 * using 1e18 precision.
 *
 * Therefore, the actual integer representation is:
 *
 *     $10,000 * 1e18 = 10,000e18
 *
 * Applying the Solidity calculation:
 *
 *     (10,000e18 * 50) / 100
 *
 *     = 500,000e18 / 100
 *
 *     = 5,000e18
 *
 * The resulting integer represents $5,000 at 18-decimal precision.
 *
 * Remember our fixed-point arithmetic rules:
 *
 * 1. The collateral value already carries a 1e18 scaling factor.
 *
 * 2. LIQUIDATION_THRESHOLD and LIQUIDATION_PRECISION are ordinary
 *    integers. They do not carry an additional 1e18 scaling factor.
 *
 * 3. Multiplying by 50 does not introduce another 1e18 scaling factor.
 *
 * 4. Dividing by 100 calculates an ordinary percentage. It does not
 *    cancel the existing 1e18 precision.
 *
 * Mathematically:
 *
 *     ((C * 1e18) * 50) / 100
 *
 *     = (C * 0.5) * 1e18
 *
 * Therefore, the result retains its original 18-decimal precision.
 *
 * STEP 3 — CALCULATE THE HEALTH FACTOR
 *
 *     return (collateralAdjustedForThreshold * PRECISION)
 *         / totalDscMinted;
 *
 * This divides the adjusted collateral value by the DSC debt.
 *
 * Remember our fixed-point division rule:
 *
 * Both collateralAdjustedForThreshold and totalDscMinted are
 * represented using 1e18 precision.
 *
 * If we divided them directly, their scaling factors would cancel,
 * leaving an ordinary integer ratio.
 *
 * To preserve 18-decimal precision in the result, we multiply
 * the numerator by PRECISION (1e18) before division.
 *
 * Using our example:
 *
 *     ($5,000e18 * 1e18) / ($3,000e18)
 *
 *     = (5,000 / 3,000) * 1e18
 *
 *     = 1.666666666666666666e18
 *
 * FINAL RESULT:
 *
 *     1666666666666666666
 *
 * Interpreted using 18-decimal precision:
 *
 *     1.666666666666666666
 *
 * STEP 4 — UNDERSTANDING THE RESULT
 *
 * A health factor of:
 *
 *     1e18 = 1.0
 *
 * This is the minimum health factor threshold in this implementation.
 *
 * A result above 1e18 means the adjusted collateral value is
 * greater than the DSC debt.
 *
 * A result below 1e18 means the adjusted collateral value is
 * less than the DSC debt.
 *
 * SUMMARY:
 *
 *     Adjusted Collateral = Collateral Value * 50 / 100
 *
 *     Health Factor = Adjusted Collateral * 1e18 / DSC Minted
 *
 * The first calculation applies a percentage.
 * The second calculates a fixed-point ratio.
 */


/* ── 4. Cyfrin__DSCEngine, LIQUIDATION BONUS ────────────────────────────────────────────
 *
 * A liquidation bonus is an additional percentage of collateral
 * awarded to a liquidator for covering another account's debt.
 *
 * The bonus is calculated using the collateral amount corresponding
 * to the debt being covered.
 *
 * Assume:
 *
 *     Debt covered       = $100
 *     ETH price          = $2,000
 *     Liquidation bonus  = 10%
 *
 * STEP 1 — CONVERT THE DEBT VALUE INTO COLLATERAL
 *
 *     Collateral Amount = USD Value / Token Price
 *
 *     = 100 / 2,000
 *
 *     = 0.05 ETH
 *
 * STEP 2 — CALCULATE THE BONUS
 *
 *     Bonus = Base Collateral * Bonus Rate / Percentage Precision
 *
 *     = 0.05 * 10 / 100
 *
 *     = 0.005 ETH
 *
 * STEP 3 — ADD THE BONUS TO THE BASE COLLATERAL
 *
 *     Total Collateral =
 *         Base Collateral + Bonus
 *
 *     = 0.05 + 0.005
 *
 *     = 0.055 ETH
 *
 * STEP 4 — VERIFY THE USD VALUE
 *
 *     0.055 * $2,000 = $110
 *
 * The liquidator covers $100 of debt and receives $110 worth
 * of collateral.
 *
 * GENERAL FORMULAS:
 *
 *     Bonus = Base Collateral * Bonus Rate / Percentage Precision
 *
 *     Total Collateral = Base Collateral + Bonus
 *
 * MATHEMATICAL PRINCIPLE:
 *
 * To calculate a percentage of a quantity, multiply the quantity
 * by the percentage rate and divide by the percentage precision.
 *
 * For example:
 *
 *     10 / 100 = 0.10 = 10%
 */


/* ── 5. Cyfrin__DSCEngine, PARTIAL LIQUIDATION ACCOUNTING ───────────────────────────────
 *
 * Partial liquidation occurs when only part of an account's
 * outstanding debt is repaid.
 *
 * The liquidator receives collateral corresponding to the repaid
 * debt, together with the liquidation bonus.
 *
 * Consequently, both collateral and debt decrease, but by
 * different amounts.
 *
 * Assume:
 *
 *     Initial Collateral Value = $140
 *     Initial Debt             = $100
 *     Liquidation Bonus        = 10%
 *     Debt Covered             = $50
 *     Liquidation Threshold    = 50%
 *
 * STEP 1 — CALCULATE THE INITIAL HEALTH FACTOR
 *
 *     Health Factor =
 *         (Collateral Value * 50 / 100) / Debt
 *
 *     = (140 * 0.5) / 100
 *
 *     = 70 / 100
 *
 *     = 0.7
 *
 * STEP 2 — CALCULATE THE COLLATERAL CORRESPONDING TO THE DEBT
 *
 * Assuming the collateral and debt are valued in USD:
 *
 *     Base Collateral Value = $50
 *
 * STEP 3 — CALCULATE THE LIQUIDATION BONUS
 *
 *     Bonus = 50 * 10 / 100
 *
 *     = $5
 *
 * STEP 4 — CALCULATE TOTAL COLLATERAL REMOVED
 *
 *     Total Collateral Removed =
 *         Base Collateral + Bonus
 *
 *     = 50 + 5
 *
 *     = $55
 *
 * STEP 5 — CALCULATE REMAINING COLLATERAL
 *
 *     Remaining Collateral =
 *         Initial Collateral - Collateral Removed
 *
 *     = 140 - 55
 *
 *     = $85
 *
 * STEP 6 — CALCULATE REMAINING DEBT
 *
 *     Remaining Debt =
 *         Initial Debt - Debt Covered
 *
 *     = 100 - 50
 *
 *     = $50
 *
 * STEP 7 — CALCULATE THE NEW HEALTH FACTOR
 *
 *     Health Factor =
 *         (Remaining Collateral * 50 / 100)
 *         / Remaining Debt
 *
 *     = (85 * 0.5) / 50
 *
 *     = 42.5 / 50
 *
 *     = 0.85
 *
 * COMPARISON:
 *
 *     Initial Health Factor   = 0.70
 *     New Health Factor       = 0.85
 *
 * The health factor improves even though collateral has decreased.
 *
 * WHY?
 *
 * The adjusted collateral value decreases by:
 *
 *     55 * 50 / 100 = $27.50
 *
 * The debt decreases by:
 *
 *     $50
 *
 * The debt reduction is proportionally greater than the reduction
 * in adjusted collateral, improving the ratio.
 *
 * MATHEMATICAL PRINCIPLE:
 *
 * When two quantities change together in a ratio, the resulting
 * ratio depends on their relative rates of change.
 *
 * A ratio can improve even when both its numerator and denominator
 * decrease, provided the denominator decreases proportionally more.
 *
 * This example assumes sufficient collateral, constant asset prices,
 * and no additional liquidation constraints.
 */