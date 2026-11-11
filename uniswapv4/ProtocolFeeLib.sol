// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 * This library handles protocol fee values used by Uniswap v4.
 *
 * It provides functionality to:
 *
 * 1. Get the protocol fee for each swap direction from a single uint24.
 * 2. Check whether the protocol fee values are valid.
 * 3. Combine the protocol fee and LP fee to calculate the total swap fee.
 */

/// @notice library of functions related to protocol fees
library ProtocolFeeLibrary {
    /// @notice Max protocol fee is 0.1% (1000 pips)
    /// @dev Increasing these values could lead to overflow in Pool.swap
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    /// @notice the protocol fee is represented in hundredths of a bip
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

/* ── 1. UNDERSTANDING PIPS ────────────────────────────────────────────
 *
 * A pool can charge two separate types of fees:
 *
 * 1. Protocol fee: The portion collected for the protocol.
 * 2. LP fee: The portion collected for liquidity providers.
 *
 * Both fees are represented using the same unit: pips.
 *
 * A pip is the unit Uniswap v4 uses to represent swap fees.
 *
 * Its fee scale is:
 *
 *     1,000,000 pips = 100%
 *
 * Therefore:
 *     10,000 pips = 1%
 *     1 pip       = 0.0001%
 *     500 pips    = 0.05%
 *     1,000 pips  = 0.1%
 *     3,000 pips  = 0.3%
 *
 * CONVERTING A PERCENTAGE TO PIPS:
 *
 * To convert a percentage into pips, multiply it by 10,000.
 *
 *     pips = percentage × 10,000
 *
 * Example:
 *
 *     0.3% × 10,000 = 3,000 pips
 *
 * CONVERTING PIPS INTO A DECIMAL FRACTION:
 *
 * Before calculating the actual fee amount, we convert the pips
 * into a decimal fraction.
 *
 * A percentage and a decimal fraction represent the same value
 * in different forms.
 *
 * To convert a percentage into a decimal fraction, divide by 100.
 *
 * Example:
 *
 *     0.3% / 100 = 0.003
 *
 * Notice the difference:
 *
 *     0.3%    = 0.003
 *     0.003%  = 0.00003
 *
 * Therefore, 0.003 is NOT 0.003%.
 * It is the decimal fraction representing 0.3%.
 *
 * Since 1,000,000 pips represents 100%, we can calculate
 * the decimal fraction directly:
 *
 *     fee fraction = pips / 1,000,000
 *
 * Example:
 *
 *     3,000 / 1,000,000 = 0.003
 *
 *     0.003 × 100 = 0.3%
 *
 * CALCULATING THE ACTUAL FEE AMOUNT:
 *
 * Once we have the decimal fraction, multiply it by the swap amount.
 *
 *     fee amount = fee fraction × swap amount
 *
 * Example:
 *
 *     Swap amount = 1,000 USDC
 *     Fee         = 3,000 pips
 *
 *     fee fraction = 3,000 / 1,000,000
 *                  = 0.003
 *
 *     fee amount = 0.003 × 1,000
 *                = 3 USDC
 *
 * Solidity uses integer arithmetic and does not directly represent
 * decimal values such as 0.003 in a uint256.
 *
 * Uniswap therefore represents fees using integer pips and performs
 * fee calculations using the corresponding integer scale.
 *
 */

    /// @notice Thresholds used for optimized bounds checks on protocol fees
    uint24 internal constant FEE_0_THRESHOLD = 1001;
    uint24 internal constant FEE_1_THRESHOLD = 1001 << 12;

/* ── 2. PROTOCOL FEE VALIDATION THRESHOLDS ─────────────────────────
 *
 * The protocol fee is stored as one uint24 containing two independent 12-bit directional fees.
 * 
 * A uint24 contains 24 bits:
 *     Upper 12 bits → oneForZero
 *     Lower 12 bits → zeroForOne
 *
 * Each value must be less than or equal to MAX_PROTOCOL_FEE (1000).
 * 
 * These constants are used by the assembly validation function
 * to check both directional fees using less-than comparisons.
 *
 * FEE_0_THRESHOLD:
 *
 *     1001
 *
 * This means a lower directional fee is valid when:
 *
 *     fee < 1001
 *
 * Therefore, values from 0 through 1000 are accepted.
 *
 * FEE_1_THRESHOLD:
 *
 *     1001 << 12
 *
 * Shifting 1001 left by 12 bits moves it into the upper
 * 12-bit section, allowing the upper directional fee to
 * be checked without first shifting it down.
 */


    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & 0xfff);
    }
/* EXTRACTING ZERO-FOR-ONE FEE:
 *
 * The zeroForOne fee occupies the lower 12 bits.
 *
 * The bitwise AND operator (&) is used with the mask 0xfff.
 *
 * A mask is a binary value used to preserve or clear selected bits.
 *
 *     0xfff =
 *     0000 0000 0000 1111 1111 1111
 *
 * The twelve lower bits are 1, while the upper bits are 0.
 *
 * During bitwise AND:
 *
 *     1 & 1 = 1
 *     1 & 0 = 0
 *     0 & 1 = 0
 *     0 & 0 = 0
 *
 * Therefore, the mask preserves the lower 12 bits and clears the upper 12 bits.
 *
 * Example:
 *
 *     Packed value:
 *     0001 1111 0100 0001 0010 1100
 *
 *     Mask:
 *     0000 0000 0000 1111 1111 1111
 *     -------------------------------- AND
 *     Result:
 *     0000 0000 0000 0001 0010 1100
 *
 *     Result = 300
 *
 * The function therefore extracts the zeroForOne fee.
 */


    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }
/* EXTRACTING ONE-FOR-ZERO FEE:
 *
 * The oneForZero fee occupies the upper 12 bits of the packed uint24.
 *
 * To extract it, we use the right-shift operator (>>).
 *
 * The expression:
 *
 *     self >> 12
 *
 * Moves every bit in self twelve positions to the right.
 *
 * WHY SHIFT BY 12?
 *
 * The packed uint24 contains two 12-bit values:
 *
 *     Upper 12 bits → oneForZero
 *     Lower 12 bits → zeroForOne
 *
 * Moving the bits twelve positions to the right places the original
 * upper 12-bit fee into the lower 12-bit position.
 *
 * EXAMPLE:
 *
 *     oneForZero = 500
 *     zeroForOne = 300
 *
 * First, represent both values using 12 bits:
 *
 *     500 = 0001 1111 0100
 *     300 = 0001 0010 1100
 *
 * The packed uint24 is:
 *
 *     0001 1111 0100 || 0001 0010 1100
 *     └─ oneForZero ─┘└─ zeroForOne ─┘
 *
 * Now perform the right shift:
 *
 *     BEFORE:
 *     0001 1111 0100 | 0001 0010 1100
 *
 *     AFTER self >> 12:
 *     0000 0000 0000 | 0001 1111 0100
 *
 * The original upper 12 bits have moved into the lower 12-bit
 * position. The original lower 12 bits have been shifted out.
 *
 * The remaining value is:
 *
 *     0001 1111 0100 = 500
 *
 * Therefore, the function returns the oneForZero fee.
 *
 */

    function isValidProtocolFee(uint24 self) internal pure returns (bool valid) {
        // Equivalent to: getZeroForOneFee(self) <= MAX_PROTOCOL_FEE && getOneForZeroFee(self) <= MAX_PROTOCOL_FEE
        assembly ("memory-safe") {
            let isZeroForOneFeeOk := lt(and(self, 0xfff), FEE_0_THRESHOLD)
            let isOneForZeroFeeOk := lt(and(self, 0xfff000), FEE_1_THRESHOLD)
            valid := and(isZeroForOneFeeOk, isOneForZeroFeeOk)
        }
    }
/* ── 4. VALIDATING PACKED PROTOCOL FEES ───────────────────────────────
 *
 * This function checks whether both directional protocol fees
 * stored inside a packed uint24 are within the permitted range.
 *
 * Each directional fee must satisfy:
 *
 *     0 <= fee <= MAX_PROTOCOL_FEE
 *
 *     0 <= fee <= 1000
 *
 * The function uses Yul assembly to perform both validations.
 *
 * UNDERSTANDING THE MASKS:
 *
 * The packed uint24 contains:
 *
 *     Upper 12 bits → oneForZero
 *     Lower 12 bits → zeroForOne
 *
 * To inspect each fee independently, we use two different masks.
 *
 * 1. LOWER 12-BIT MASK:
 *
 *     0xfff
 *
 *     Binary:
 *
 *     0000 0000 0000 1111 1111 1111
 *
 *     This mask contains twelve 1 bits in the lower positions.
 *
 *     When AND is performed, those lower twelve bits are preserved,
 *     while the upper twelve bits are cleared.
 *
 *     Example:
 *
 *     self:
 *     0001 1111 0100 0001 0010 1100
 *
 *     mask:
 *     0000 0000 0000 1111 1111 1111
 *     -------------------------------- AND
 *
 *     result:
 *     0000 0000 0000 0001 0010 1100
 *
 *     The result is 300, the zeroForOne fee.
 *
 * 2. UPPER 12-BIT MASK:
 *
 *     0xfff000
 *
 *     Binary:
 *
 *     1111 1111 1111 0000 0000 0000
 *
 *     This mask contains twelve 1 bits in the upper positions.
 *
 *     When AND is performed, the upper twelve bits are preserved,
 *     while the lower twelve bits are cleared.
 *
 *     Example:
 *
 *     self:
 *     0001 1111 0100 0001 0010 1100
 *
 *     mask:
 *     1111 1111 1111 0000 0000 0000
 *     -------------------------------- AND
 *
 *     result:
 *     0001 1111 0100 0000 0000 0000
 *
 *     The result is 500 shifted left by 12 positions.
 *
 * IMPORTANT:
 *
 *     The first mask moves no bits.
 *     The second mask also moves no bits.
 *
 *     They simply preserve the selected bits and clear the rest.
 *
 * UNDERSTANDING THE THRESHOLDS:
 *
 * The function uses:
 *
 *     FEE_0_THRESHOLD = 1001
 *     FEE_1_THRESHOLD = 1001 << 12
 *
 * Why 1001 instead of 1000?
 *
 * The Yul LT opcode checks whether the first value is strictly
 * less than the second value.
 *
 *     1000 < 1001 = true
 *     1001 < 1001 = false
 *
 * Therefore, comparing against 1001 allows the maximum permitted
 * fee of 1000 while rejecting 1001 and above.
 *
 * CHECKING THE ZERO-FOR-ONE FEE:
 *
 *     lt(and(self, 0xfff), FEE_0_THRESHOLD)
 *
 * First:
 *
 *     and(self, 0xfff)
 *
 * Isolates the lower 12 bits.
 *
 * Using our example:
 *
 *     zeroForOne = 300
 *
 * The comparison becomes:
 *
 *     lt(300, 1001)
 *
 *     300 < 1001 = true
 *
 * The result is 1.
 *
 * CHECKING THE ONE-FOR-ZERO FEE:
 *
 *     lt(and(self, 0xfff000), FEE_1_THRESHOLD)
 *
 * First:
 *
 *     and(self, 0xfff000)
 *
 * Isolates the upper 12 bits without moving them.
 *
 * Using our example:
 *
 *     oneForZero = 500
 *
 * The isolated value is:
 *
 *     500 << 12
 *
 * The threshold is:
 *
 *     1001 << 12
 *
 * The comparison therefore becomes:
 *
 *     (500 << 12) < (1001 << 12)
 *
 * Since both values are shifted by the same number of positions,
 * the comparison is equivalent to:
 *
 *     500 < 1001
 *
 *     true
 *
 * The result is also 1.
 *
 * WHY NOT SHIFT THE UPPER FEE DOWN?
 *
 * We could extract the upper fee by shifting it right by 12
 * and then comparing it against 1001.
 *
 * However, this implementation keeps the upper fee in its
 * original position and shifts the threshold left instead.
 *
 * Both approaches can produce the same validation result.
 *
 * COMBINING THE VALIDATION RESULTS:
 *
 *     valid := and(isZeroForOneFeeOk, isOneForZeroFeeOk)
 *
 * Each LT comparison returns either:
 *
 *     1 = true
 *     0 = false
 *
 * The final AND requires both results to be 1.
 *
 *     1 AND 1 = 1
 *     1 AND 0 = 0
 *     0 AND 1 = 0
 *     0 AND 0 = 0
 *
 * Example:
 *
 *     zeroForOne = 300
 *     oneForZero = 500
 *
 *     zeroForOne check = 1
 *     oneForZero check = 1
 *
 *     valid = 1 AND 1 = true
 *
 * INVALID EXAMPLE:
 *
 *     zeroForOne = 300
 *     oneForZero = 1001
 *
 *     zeroForOne check = 1
 *     oneForZero check = 0
 *
 *     valid = 1 AND 0 = false
 *
 * The function returns true only when both directional fees
 * are valid.
 *
 */

    // The protocol fee is taken from the input amount first and then the LP fee is taken from the remaining
    // The swap fee is capped at 100%
    // Equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000 (rounded up)
    /// @dev here `self` is just a single direction's protocol fee, not a packed type of 2 protocol fees
    function calculateSwapFee(uint16 self, uint24 lpFee) internal pure returns (uint24 swapFee) {
        // protocolFee + lpFee - (protocolFee * lpFee / 1_000_000)
        assembly ("memory-safe") {
            self := and(self, 0xfff)
            lpFee := and(lpFee, 0xffffff)
            let numerator := mul(self, lpFee)
            swapFee := sub(add(self, lpFee), div(numerator, PIPS_DENOMINATOR))
        }
    }
/* ── 5. CALCULATING THE COMBINED SWAP FEE ─────────────────────────────
 *
 * Remember, swap can incur two separate fees:
 *
 * 1. Protocol fee: The portion collected by the protocol.
 * 2. LP fee: The portion collected for liquidity providers.
 *
 * Both fees are expressed in pips, where:
 *
 *     1,000,000 pips = 100%
 *
 * IMPORTANT:
 *
 * The `self` parameter is a single directional protocol fee.
 * It is NOT the packed uint24 containing both directional fees.
 *
 * Before calling this function, the appropriate directional fee
 * must already have been selected.
 *
 * For example:
 *
 *     uint24 packedFee = ...;
 *
 *     uint16 protocolFee = zeroForOne
 *         ? getZeroForOneFee(packedFee)
 *         : getOneForZeroFee(packedFee);
 *
 * The selected protocol fee is then combined with the LP fee.
 *
 *
 * ── UNDERSTANDING HOW THE TWO FEES ARE COMBINED ──────────────────────
 *
 * The protocol fee is deducted from the swap input first.
 *
 * The LP fee is then calculated on the amount remaining after
 * the protocol fee has been deducted.
 *
 * This means the LP fee is NOT calculated on the original
 * swap amount.
 *
 * Let's understand this using an actual swap.
 *
 * EXAMPLE:
 *
 *     Swap input amount = 1,000 USDC
 *
 *     Protocol fee = 1,000 pips = 0.1%
 *     LP fee       = 3,000 pips = 0.3%
 *
 * STEP 1: CALCULATE THE PROTOCOL FEE
 *
 * The protocol fee is 0.1% of the original swap amount.
 *
 *     0.1% / 100 = 0.001
 *
 *     Protocol fee amount:
 *
 *     1,000 USDC × 0.001 = 1 USDC
 *
 * After deducting the protocol fee:
 *
 *     1,000 - 1 = 999 USDC
 *
 * The remaining amount is 999 USDC.
 *
 * STEP 2: CALCULATE THE LP FEE
 *
 * The LP fee is 0.3%, but it is calculated on the remaining
 * 999 USDC rather than the original 1,000 USDC.
 *
 *     0.3% / 100 = 0.003
 *
 *     LP fee amount:
 *
 *     999 USDC × 0.003 = 2.997 USDC
 *
 * STEP 3: ADD BOTH FEES
 *
 *     Protocol fee = 1 USDC
 *     LP fee       = 2.997 USDC
 *
 *     Total fee = 1 + 2.997
 *
 *     Total fee = 3.997 USDC
 *
 * Therefore, the combined fee charged against the original
 * 1,000 USDC input is 3.997 USDC.
 *
 * The remaining amount is:
 *
 *     1,000 - 3.997 = 996.003 USDC
 *
 *
 * ── DERIVING THE COMBINED FEE FORMULA ─────────────────────────────────
 *
 * We can calculate the combined fee directly using pips.
 *
 * Remember:
 *
 *     1,000,000 pips = 100%
 *
 * Let:
 *
 *     P = protocol fee in pips
 *     L = LP fee in pips
 *
 * First, calculate the fraction remaining after the protocol fee.
 *
 *     Remaining fraction = (1,000,000 - P) / 1,000,000
 *
 * Why?
 *
 * Because the entire swap amount represents 1,000,000 pips.
 *
 * If the protocol takes P pips, the remaining portion is:
 *
 *     1,000,000 - P
 *
 * For our example:
 *
 *     P = 1,000
 *
 *     Remaining fraction:
 *
 *     (1,000,000 - 1,000) / 1,000,000
 *
 *     = 999,000 / 1,000,000
 *
 *     = 0.999
 *
 * This means 99.9% of the original amount remains after
 * the protocol fee.
 *
 * Next, calculate the LP fee on that remaining portion.
 *
 *     LP fee on remaining amount =
 *
 *     L × (1,000,000 - P) / 1,000,000
 *
 * Substituting our values:
 *
 *     3,000 × 999,000 / 1,000,000
 *
 *     = 2,997,000,000 / 1,000,000
 *
 *     = 2,997 pips
 *
 * The combined fee is the protocol fee plus the LP fee
 * calculated on the remaining amount.
 *
 *     swapFee = P + L × (1,000,000 - P) / 1,000,000
 *
 * Therefore:
 *
 *     swapFee = 1,000 + 2,997
 *
 *     swapFee = 3,997 pips
 *
 *
 * ── WHY DOES THE FORMULA SUBTRACT AN OVERLAP? ─────────────────────────
 *
 * The same formula can be rewritten to make the subtraction clearer.
 *
 * Starting with:
 *
 *     swapFee = P + L × (1,000,000 - P) / 1,000,000
 *
 * Expand the multiplication:
 *
 *     swapFee = P + L × 1,000,000 / 1,000,000
 *                 - L × P / 1,000,000
 *
 * Simplifying:
 *
 *     swapFee = P + L - (P × L) / 1,000,000
 *
 * The term:
 *
 *     (P × L) / 1,000,000
 *
 * Is the overlap that must be subtracted.
 *
 * WHY IS IT SUBTRACTED?
 *
 * If we simply added both fees:
 *
 *     1,000 + 3,000 = 4,000 pips
 *
 * We would be calculating the LP fee as though it were charged
 * on the original swap amount.
 *
 * But the LP fee is charged only on the amount remaining after
 * the protocol fee.
 *
 * Therefore, we subtract the portion of the LP fee that would
 * have been charged on the amount already taken by the protocol.
 *
 * This is why:
 *
 *     Combined fee = Protocol fee + LP fee - Overlap
 *
 * Using our example:
 *
 *     Protocol fee = 1,000 pips
 *     LP fee       = 3,000 pips
 *
 *     Overlap:
 *
 *     (1,000 × 3,000) / 1,000,000
 *
 *     = 3,000,000 / 1,000,000
 *
 *     = 3 pips
 *
 *     Combined fee:
 *
 *     1,000 + 3,000 - 3 = 3,997 pips
 *
 * Both mathematical expressions produce the same result.
 *
 * The expanded expression is the one used in the assembly.
 *
 *
 * ── CONVERTING THE RESULT BACK TO A PERCENTAGE ────────────────────────
 *
 * We obtained:
 *
 *     3,997 pips
 *
 * To convert pips into a percentage, divide by 10,000.
 *
 *     3,997 / 10,000 = 0.3997%
 *
 * Therefore:
 *
 *     1,000 pips = 0.1%
 *     3,000 pips = 0.3%
 *     3,997 pips = 0.3997%
 *
 * Notice that the combined fee is slightly less than 0.4%.
 *
 * This is because the LP fee is calculated on the remaining
 * amount rather than the original swap amount.
 *
 *
 * ── INTEGER DIVISION AND ROUNDING ─────────────────────────────────────
 *
 * Solidity integer division discards the fractional remainder.
 *
 * For example:
 *
 *     10 / 3 = 3
 *
 * Not 3.333333...
 *
 * In this formula:
 *
 *     swapFee = P + L - (P × L / 1,000,000)
 *
 * Integer division happens in the overlap calculation.
 *
 * Consider:
 *
 *     P = 1,001 pips
 *     L = 3,000 pips
 *
 * Calculate the overlap:
 *
 *     1,001 × 3,000 = 3,003,000
 *
 *     3,003,000 / 1,000,000 = 3.003
 *
 * Solidity evaluates this division as:
 *
 *     3,003,000 / 1,000,000 = 3
 *
 * The fractional 0.003 is discarded.
 *
 * Now calculate the combined fee:
 *
 *     1,001 + 3,000 - 3
 *
 *     = 3,998 pips
 *
 * The exact mathematical result before integer truncation
 * would be:
 *
 *     1,001 + 3,000 - 3.003
 *
 *     = 3,997.997 pips
 *
 * Solidity returns 3,998 pips.
 *
 * Therefore, truncating the overlap down causes the final
 * combined fee to round UP to the next whole pip when the
 * exact result contains a fractional pip.
 *
 * If the overlap divides evenly, there is no fractional
 * remainder and no rounding difference.
 *
 *
 * ── THE COMBINED FEE CANNOT EXCEED 100% ───────────────────────────────
 *
 * Assuming both input fees are within their intended ranges,
 * the combined fee cannot exceed 1,000,000 pips.
 *
 * This follows from the formula:
 *
 *     swapFee = P + L × (1,000,000 - P) / 1,000,000
 *
 * If the LP fee is at most 1,000,000 pips:
 *
 *     L × (1,000,000 - P) / 1,000,000
 *
 * Cannot exceed the remaining portion:
 *
 *     1,000,000 - P
 *
 * Therefore:
 *
 *     swapFee <= P + (1,000,000 - P)
 *
 *     swapFee <= 1,000,000
 *
 * This is the mathematical reason the combined fee is capped
 * at 100%, assuming the input fees satisfy their intended bounds.
 */


/*
 * ── 6. UNDERSTANDING THE ASSEMBLY IMPLEMENTATION ────────────────────
 *
 * The assembly block implements the combined fee formula using
 * Yul instructions.
 *
 * The Solidity expression:
 *
 *     P + L - (P × L / 1,000,000)
 *
 * Is implemented using:
 *
 *     and()
 *     mul()
 *     div()
 *     add()
 *     sub()
 *
 *
 * STEP 1: MASK THE PROTOCOL FEE
 *
 *     self := and(self, 0xfff)
 *
 * The `and` instruction performs a bitwise AND.
 *
 * The mask:
 *
 *     0xfff
 *
 * Contains twelve 1 bits in its lower positions.
 *
 * It preserves the lower 12 bits and clears all higher bits.
 *
 * Why?
 *
 * Although `self` is declared as uint16, the intended
 * directional protocol fee occupies only 12 bits.
 *
 * Example:
 *
 *     self = 0x01f4 = 500
 *
 *     self in binary:
 *
 *     0000 0001 1111 0100
 *
 *     mask:
 *
 *     0000 1111 1111 1111
 *     ------------------- AND
 *
 *     result:
 *
 *     0000 0001 1111 0100
 *
 *     result = 500
 *
 * In this example, the value is already within 12 bits,
 * so masking does not change it.
 *
 * If higher bits were set, the mask would clear them.
 *
 * IMPORTANT:
 *
 * This operation does not validate that the fee is at most 1000.
 * It only restricts the value to its lower 12 bits.
 *
 *
 * STEP 2: MASK THE LP FEE
 *
 *     lpFee := and(lpFee, 0xffffff)
 *
 * The LP fee is declared as uint24.
 *
 * The mask:
 *
 *     0xffffff
 *
 * Contains twenty-four 1 bits.
 *
 * Therefore, it preserves the lower 24 bits and clears
 * any bits above that range.
 *
 * Since lpFee is already declared as uint24 in Solidity,
 * it is normally already within 24 bits.
 *
 * This mask makes the intended 24-bit boundary explicit
 * inside the assembly calculation.
 *
 *
 * STEP 3: MULTIPLY BOTH FEES
 *
 *     let numerator := mul(self, lpFee)
 *
 * The `mul` instruction multiplies two values.
 *
 * It calculates:
 *
 *     numerator = P × L
 *
 * Using our earlier example:
 *
 *     P = 1,000
 *     L = 3,000
 *
 *     numerator = 1,000 × 3,000
 *
 *     numerator = 3,000,000
 *
 * This multiplication produces the numerator used
 * to calculate the overlap.
 *
 *
 * STEP 4: DIVIDE THE OVERLAP
 *
 *     div(numerator, PIPS_DENOMINATOR)
 *
 * The `div` instruction performs unsigned integer division.
 *
 * PIPS_DENOMINATOR is:
 *
 *     1,000,000
 *
 * Therefore:
 *
 *     overlap = 3,000,000 / 1,000,000
 *
 *     overlap = 3
 *
 * The result is 3 pips.
 *
 * If the division produces a fractional remainder,
 * that remainder is discarded.
 *
 *
 * STEP 5: ADD THE TWO FEES AND SUBTRACT THE OVERLAP
 *
 *     swapFee := sub(
 *         add(self, lpFee),
 *         div(numerator, PIPS_DENOMINATOR)
 *     )
 *
 * The `add` instruction first calculates:
 *
 *     P + L
 *
 *     1,000 + 3,000 = 4,000
 *
 * The `sub` instruction then subtracts the overlap:
 *
 *     4,000 - 3 = 3,997
 *
 * The final result is:
 *
 *     swapFee = 3,997 pips
 *
 *     swapFee = 0.3997%
 *
 */
}