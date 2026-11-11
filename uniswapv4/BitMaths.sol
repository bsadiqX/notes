// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* BitMath
 * This library finds the positions of set bits in a non-zero uint256.
 * A set bit is a bit whose value is 1.
 *
 * Bit positions are counted from right to left, starting at index 0.
 *
 * Example:
 *   x = 40
 *   Binary: 101000
 *
 *   Bit index:  5 4 3 2 1 0
 *   Bit value:  1 0 1 0 0 0
 *
 *   MSB = 5 (leftmost set bit).
 *   LSB = 3 (rightmost set bit).
 *
 * These operations are useful when working with bitmaps, packed
 * values, flags, and other bit-based data structures.
*/

/// @title BitMath
/// @dev This library provides functionality for computing bit properties of an unsigned integer
/// @author Solady (https://github.com/Vectorized/solady/blob/8200a70e8dc2a77ecb074fc2e99a2a0d36547522/src/utils/LibBit.sol)
library BitMath {
    /// @notice Returns the index of the most significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @param x the value for which to compute the most significant bit, must be greater than 0
    /// @return r the index of the most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);
        /* FINDING THE MOST SIGNIFICANT BIT:
         * The goal is to find the position of the leftmost set bit.
         *
         * Instead of checking all 256 bit positions individually, the algorithm progressively narrows 
         * down the possible position using comparisons.
         *
         * It checks ranges of:
         *   128, 64, 32, 16 and 8 bits.
         *
         * The variable r stores the accumulated shift distance.
        */
        assembly ("memory-safe") {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            /* 1. THIS CHECK THE UPPER 128 BITS
             *
             * lt(a, b) returns:
             *
             *   1 if a < b.
             *   0 if a >= b.
             *
             * The constant:
             *   0xffffffffffffffffffffffffffffffff is the maximum uint128 value: 2^128 - 1.
             *
             *   If x is greater than this value, its highest set bit must be in positions 128 through 255.
             *
             * shl(7, 1) = 128.
             * shl(7, 0) = 0.
             *
             * Therefore:
             *
             * If lt() returns 1:
             *   r becomes 128.
             *
             * If lt() returns 0:
             *   r becomes 0.
             *
             * Note:
             * Returning 0 does not skip the next instruction.
             * Returning 1 does not terminate the algorithm.
             *
             * Both results allow execution to continue.
             * The difference is the value stored in r.
             *
             * That value determines how far x is shifted during the next comparison.
            */

            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            /* 2. CHECK THE NEXT 64 BITS
             *
             * r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
             * 
             * shr(r, x) shifts x right by the distance stored in r.
             *
             * If r = 128:
             *   x is shifted right by 128 bits.
             *
             * If r = 0:
             *   x remains unchanged.
             *
             * WHY DO WE SHIFT x RIGHT BY r?
             *
             * The previous comparison may have established that the
             * highest set bit is within the upper 128 bits.
             *
             * If so, r = 128.
             *
             * We shift x right by 128 to bring that remaining upper
             * portion down, allowing us to check it against uint64.max.
             *
             * The shift does not change the original position of the bit.
             * We keep the distance shifted in r so we can recover its original position later.
             *
             * EXAMPLE:
             *
             * Let: x = 2^100
             *
             * Its highest set bit is at index 100.
             *
             * FIRST COMPARISON:
             *
             *     lt(uint128.max, x) = 0
             *
             * Because 2^100 is smaller than uint128.max.
             *
             * Therefore:
             *
             *     r = 0
             *
             * SECOND COMPARISON:
             *
             *     shr(r, x)
             *
             * Since r = 0:
             *
             *     shr(0, 2^100) = 2^100
             *
             * Nothing is shifted because we have not accumulated any offset yet.
             *
             * Now compare the remaining value against uint64.max:
             *
             *     lt(uint64.max, 2^100) = 1
             *
             * Because 2^100 is greater than uint64.max.
             *
             * Therefore:
             *
             *     shl(6, 1) = 64
             *     or(0, 64) = 64
             *
             * Now r = 64.
             *
             * WHAT IF THE COMPARISON RETURNS 0?
             *
             *     shl(6, 0) = 0
             *
             *     or(r, 0) = r
             *
             * The accumulated offset remains unchanged.
             *
             * Whether the comparison returns 0 or 1, the algorithm continues to the next instruction.
             * The next comparison uses the updated r to shift x and examine the remaining higher portion.
            */

            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            /*
             * 3. CONTINUED NARROWING DOWN THE RANGE
             *
             * The same process continues with smaller ranges.
             *
             * uint32.max = 0xffffffff
             * uint16.max = 0xffff
             * uint8.max  = 0xff
             *
             * Each comparison checks whether the remaining value is greater than the corresponding maximum.
             *
             * If the comparison returns 1:
             *   The corresponding shift amount is included in r.
             *
             * If the comparison returns 0:
             *   Zero is included, so r remains unchanged.
             *
             * Neither result skips the following instruction.
             *
             * The accumulated shift distance is therefore:
             *
             *   128 + 64 + 32 + 16 + 8
             *
             * with only the required distances included.
            */

            // forgefmt: disable-next-item
            r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020500060203020504000106050205030304010505030400000000))
            /*
             * 4. FINAL LOOKUP: FIND THE POSITION WITHIN 8 BITS
             *
             * After the previous comparisons, shifting x right
             * by r leaves a value between 1 and 255.
             *
             * This means the highest set bit is now somewhere within the lowest 8 bit positions.
             * We use a lookup technique to find its exact position.
             *
             * The expression: shr(r, x) gives us the remaining value.
             *
             * The remaining value is then used as the shift amount for the first lookup constant:
             *
             *   0x8421084210842108cc6318c6db6d54be
             *
             * The operation:
             *
             *   shr(shr(r, x), constant)
             *
             * shifts that constant right by the remaining value.
             *
             * Next:
             *
             *   and(0x1f, result)
             *
             * 0x1f in binary is:
             *
             *   00011111
             *
             * AND keeps only the lowest 5 bits.
             * This produces an index between 0 and 31.
             *
             * Then: byte(index, lookupTable)
             * extracts the byte at that index from the 32-byte lookup table.
             *
             * The table has been arranged so that the selected byte gives the MSB position 
             * within the remaining 8-bit value (0 through 7).
             *
             * Finally:
             *
             *   or(r, lookupResult)
             *
             * combines the position found in the final 8-bit range
             * with the shift distance already stored in r.
             *
             * 
             * EXAMPLE 1: x = 40
             *
             * Binary:
             *
             *   00101000
             *
             * The highest set bit is at index 5.
             *
             * All five range comparisons return 0.
             *
             * Therefore:
             *
             *   r = 0
             *
             * The remaining value is:
             *
             *   shr(0, 40) = 40
             *
             * The first lookup operation produces:
             *
             *   and(0x1f, shr(40, lookupConstant)) = 24
             *
             * The lookup table returns:
             *
             *   byte(24, lookupTable) = 5
             *
             * Finally:
             *
             *   or(0, 5) = 5
             *
             * The function returns 5.
             *
             *
            */
        }
    }
/*
 * EXAMPLE 2: x = 2^200
 *
 * Our goal is to find the position of the highest set bit.
 *
 * Since x = 2^200, its only set bit is at index 200.
 *
 * The algorithm starts with r = 0.
 *
 * Remember:
 *
 * - x is the original number. We do not permanently modify it.
 * - r stores the accumulated bit-position offset.
 * - shr(r, x) temporarily shifts x right by the offset in r.
 * - shl(n, 1) produces 2^n, which is the next offset to add.
 * - or() combines the newly discovered offset with r.
 *
 * We are progressively narrowing down the position of the highest set bit.
 *
 * 1. FIRST COMPARISON: CHECK THE UPPER 128 BITS
 *
 *     r := shl(7, lt(uint128.max, x))
 *
 * First, compare:
 *
 *     lt(uint128.max, 2^200)
 *
 * Remember that lt(a, b) checks whether a < b.
 *
 * Since:
 *
 *     2^200 > 2^128 - 1
 *
 * The comparison returns 1.
 *
 * Now:
 *
 *     shl(7, 1) = 128
 *
 * We are shifting the value 1 left by 7 positions.
 * We are NOT shifting x.
 *
 * Therefore:
 *
 *     r = 128
 *
 * What have we established?
 *
 * The highest set bit is in the upper 128-bit range,
 * meaning its original position is between 128 and 255.
 *
 * The offset 128 is now stored in r.
 *
 *
 * 2. SECOND COMPARISON: CHECK THE NEXT 64 BITS
 *
 *     r := or(r, shl(6, lt(uint64.max, shr(r, x))))
 *
 * We now have:
 *
 *     r = 128
 *
 * First, evaluate:
 *
 *     shr(r, x)
 *
 * This means:
 *
 *     shr(128, 2^200)
 *
 * We shift x right by 128 positions.
 *
 * Mathematically:
 *
 *     2^200 / 2^128 = 2^72
 *
 * Therefore:
 *
 *     shr(128, x) = 2^72
 *
 * Why are we doing this?
 *
 * We already accounted for the lower 128 positions when we added 128 to r.
 *
 * Shifting x right by 128 brings the remaining higher
 * portion down so that we can check it against uint64.max.
 *
 * Notice that the original set bit was at index 200.
 * After shifting right by 128, it is now at index 72.
 *
 * We have not lost its original position because r
 * remembers the 128 positions we shifted away.
 *
 * Now perform the comparison:
 *
 *     lt(uint64.max, 2^72)
 *
 * Since:
 *
 *     2^72 > 2^64 - 1
 *
 * The comparison returns 1.
 *
 * Next:
 *
 *     shl(6, 1) = 64
 *
 * We are shifting the value 1 left by 6 positions to calculate the next offset.
 *
 * Now combine it with the existing r:
 *
 *     or(128, 64)
 *
 * In binary:
 *
 *     128 = 10000000
 *      64 = 01000000
 *           --------
 *      OR = 11000000 = 192
 *
 * Therefore:
 *
 *     r = 192
 *
 * What have we established?
 *
 * The highest set bit is in the original range 192 to 255.
 *
 * The accumulated offset is now 192.
 *
 *
 * 3. THIRD COMPARISON: CHECK THE NEXT 32 BITS
 *
 *     r := or(r, shl(5, lt(uint32.max, shr(r, x))))
 *
 * We now have:
 *
 *     r = 192
 *
 * First, shift the original x right by 192 positions:
 *
 *     shr(192, 2^200)
 *
 * Mathematically:
 *
 *     2^200 / 2^192 = 2^8
 *
 * Therefore:
 *
 *     shr(192, x) = 2^8 = 256
 *
 * Notice what happened:
 *
 * - Original bit position: 200
 * - Positions shifted away: 192
 * - Remaining bit position: 8
 *
 * We now compare the remaining value against uint32.max:
 *
 *     lt(uint32.max, 256)
 *
 * Since 256 is smaller than 2^32 - 1, the comparison
 * returns 0.
 *
 * Therefore:
 *
 *     shl(5, 0) = 0
 *
 * Combine with the existing offset:
 *
 *     or(192, 0) = 192
 *
 * So:
 *
 *     r remains 192.
 *
 * IMPORTANT:
 *
 * Returning 0 does not skip the next comparison.
 * It simply means we do not add another 32 to r.
 *
 * The next comparison still executes.
 *
 *
 * 4. FOURTH COMPARISON: CHECK THE NEXT 16 BITS
 *
 *     r := or(r, shl(4, lt(uint16.max, shr(r, x))))
 *
 * Since r is still 192:
 *
 *     shr(192, x) = 256
 *
 * We compare:
 *
 *     lt(uint16.max, 256)
 *
 * Since:
 *
 *     256 < 2^16 - 1
 *
 * The comparison returns 0.
 *
 * Therefore:
 *
 *     shl(4, 0) = 0
 *
 * Combine:
 *
 *     or(192, 0) = 192
 *
 * So r remains 192.
 *
 * Again, the algorithm continues.
 *
 *
 * 5. FIFTH COMPARISON: CHECK THE NEXT 8 BITS
 *
 *     r := or(r, shl(3, lt(uint8.max, shr(r, x))))
 *
 * We still have:
 *
 *     r = 192
 *
 * Therefore:
 *
 *     shr(192, x) = 256
 *
 * Now compare:
 *
 *     lt(uint8.max, 256)
 *
 * Since:
 *
 *     256 > 255
 *
 * The comparison returns 1.
 *
 * Therefore:
 *
 *     shl(3, 1) = 8
 *
 * Combine with the existing offset:
 *
 *     or(192, 8)
 *
 * In binary:
 *
 *     192 = 11000000
 *       8 = 00001000
 *            --------
 *      OR = 11001000 = 200
 *
 * Therefore:
 *
 *     r = 200
 *
 * What have we established?
 *
 * We have now accounted for 200 positions.
 *
 * The highest set bit is within the lowest 8 positions
 * of the remaining value.
 *
 *
 * 6. FINAL LOOKUP: FIND THE EXACT POSITION WITHIN 8 BITS
 *
 * At this point:
 *
 *     r = 200
 *
 * The remaining value is:
 *
 *     shr(200, x)
 *
 *     2^200 >> 200 = 1
 *
 * In binary:
 *
 *     00000001
 *
 * The final lookup table determines the highest set bit
 * within this remaining 8-bit value.
 *
 * Since the remaining value is 1, its highest set bit
 * is at index 0.
 *
 * Therefore, the lookup returns:
 *
 *     0
 *
 * The final operation combines this result with r:
 *
 *     or(200, 0) = 200
 *
 *
 * FINAL RESULT:
 *
 *     mostSignificantBit(2^200) = 200
 *
 * The original highest set bit was at index 200,
 * and the algorithm correctly returns 200.
*/

    /// @notice Returns the index of the least significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @param x the value for which to compute the least significant bit, must be greater than 0
    /// @return r the index of the least significant bit
    function leastSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);
        /*
         * FINDING THE LEAST SIGNIFICANT BIT (LSB)
         *
         * The goal is to find the index of the rightmost set bit in x.
         *
         * A set bit is a bit whose value is 1.
         *
         * Bit positions start at 0 from the right.
         *
         * Example: x = 40
         *
         *     Binary: 00101000
         *
         *     Bit index:  7 6 5 4 3 2 1 0
         *     Bit value:  0 0 1 0 1 0 0 0
         *
         * The rightmost set bit is at index 3.
         *
         * Unlike mostSignificantBit(), which progressively narrows
         * down a range using comparisons, this function uses a
         * different approach:
         *
         * 1. Isolate the rightmost set bit.
         * 2. Find its upper 3 position bits using a lookup technique.
         * 3. Find its lower 5 position bits using another lookup.
         * 4. Combine both parts to obtain the original bit index.
        */

        assembly ("memory-safe") {
            // Isolate the least significant bit.
            x := and(x, sub(0, x))
            // For the upper 3 bits of the result, use a De Bruijn-like lookup.
            // Credit to adhusson: https://blog.adhusson.com/cheap-find-first-set-evm/
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            // For the lower 5 bits of the result, use a De Bruijn lookup.
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
        /*
        * 1. ISOLATE THE RIGHTMOST SET BIT
        *
        *     x := and(x, sub(0, x))
        *
        * This operation is commonly written as:
        *
        *     x & -x
        *
        * First, understand what sub(0, x) does.
        *
        *     sub(0, x)
        *
        * Calculates 0 - x.
        *
        * Since EVM arithmetic operates on 256-bit words, this
        * subtraction wraps around modulo 2^256.
        *
        * This gives us the two's-complement representation of -x.
        *
        * In two's-complement arithmetic:
        *
        *     -x = ~x + 1
        *
        * We then perform a bitwise AND between x and -x.
        *
        * WHY DOES THIS ISOLATE THE RIGHTMOST SET BIT?
        *
        * The two's-complement operation flips the bits of x
        * and adds 1.
        *
        * This causes the rightmost set bit of x to remain set
        * in -x, while the bits to its right become zero.
        *
        * The AND operation therefore preserves that rightmost
        * set bit and clears the other set bits.
        *
        * EXAMPLE: x = 40
        *
        *     x = 40
        *
        *     Binary:
        *
        *         00101000
        *
        * Calculate -x:
        *
        *     -40 = 2^256 - 40
        *
        * For illustration, using only 8 bits:
        *
        *     x  = 00101000
        *     -x = 11011000
        *
        * Perform the AND:
        *
        *         00101000
        *       & 11011000
        *       ----------
        *         00001000
        *
        * Therefore:
        *
        *     x & -x = 8
        *
        * The original number had set bits at positions 5 and 3.
        * After isolation, only the set bit at position 3 remains.
        *
        * IMPORTANT:
        * The value of x inside the assembly has now been replaced with the isolated bit.
        * It is no longer 40. It is now 8.
        *
        * This makes the remaining lookup operations easier because
        * they no longer need to distinguish between multiple set bits.
        *
        *
        *  * 2. FIND THE UPPER 3 BITS OF THE BIT POSITION
        *
        * The next expression is:
        *
        *     r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
        *         0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
        *         0x8040405543005266443200005020610674053026020000107506200176117077)))
        *
        * This looks complicated because several operations are combined into one expression.
        * The purpose is to determine which group of 32 bit positions contains the isolated set bit.
        *
        * There are 256 possible bit positions:
        *
        *     0 through 255.
        *
        * We can divide these positions into eight groups:
        *
        *     Group 0: positions   0 - 31
        *     Group 1: positions  32 - 63
        *     Group 2: positions  64 - 95
        *     Group 3: positions  96 - 127
        *     Group 4: positions 128 - 159
        *     Group 5: positions 160 - 191
        *     Group 6: positions 192 - 223
        *     Group 7: positions 224 - 255
        *
        * Each group contains 32 positions.
        *
        * The first lookup determines which of these eight groups
        * contains our isolated bit.
        *
        * The constants are carefully chosen lookup machinery.
        * They encode the mapping from an isolated bit position
        * to its corresponding group.
        *
        * BREAKING DOWN THE OPERATIONS:
        *
        * A. MUL
        *
        *     mul(x, firstConstant)
        *
        * Multiplies the isolated bit by a carefully selected constant.
        *
        * Since x contains exactly one set bit, the multiplication
        * produces a pattern that depends on that bit's position.
        *
        * B. SHR(250, ...)
        *
        *     shr(250, multiplicationResult)
        *
        * Shifts the multiplication result right by 250 positions.
        *
        * This brings the upper 6 bits of the 256-bit result down to the lowest positions.
        *
        * C. SHL(2, ...)
        *
        *     shl(2, previousResult)
        *
        * Shifts that intermediate result left by 2 positions.
        *
        * This produces a shift amount used by the next lookup.
        *
        * D. SHL(..., secondConstant)
        *
        *     shl(intermediateShift, secondConstant)
        *
        * Shifts the second lookup constant.
        *
        * The selected position in this constant encodes the
        * group containing the isolated bit.
        *
        * E. SHR(252, ...)
        *
        *     shr(252, previousResult)
        *
        * Extracts the upper 4 bits of the shifted lookup constant.
        *
        * The resulting value identifies one of the eight groups,
        * giving a value from 0 through 7.
        *
        * F. SHL(5, ...)
        *
        *     shl(5, group)
        *
        * Each group contains 32 positions.
        *
        * Therefore, multiplying the group number by 32 gives
        * the starting bit position of that group.
        *
        * Shifting left by 5 is equivalent to multiplying by 2^5, which is 32.
        *
        * For example:
        *
        *     shl(5, 0) = 0
        *     shl(5, 1) = 32
        *     shl(5, 2) = 64
        *     shl(5, 3) = 96
        *
        * The result is stored in r.
        *
        * At this point, r contains the upper portion of the
        * original bit index, expressed as a multiple of 32.
        *
        *
        * 3. FIND THE LOWER 5 BITS OF THE BIT POSITION
        *
        * The next expression is:
        *
        *     r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
        *         0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        *
        * We have already identified the group of 32 positions containing the isolated bit.
        *
        * Now we need to find the exact position within that group.
        *
        * The lower 5 bits of a bit index can represent values from 0 through 31.
        *
        * BREAKING DOWN THE OPERATIONS:
        *
        * A. SHR(r, x)
        *
        *     shr(r, x)
        *
        * Shifts the isolated bit right by the group offset already stored in r.
        *
        * This removes the upper portion of its position and
        * brings the isolated bit down within its group of 32.
        *
        * For example, if the original bit was at index 200:
        *
        *     r = 192
        *
        *     shr(192, 2^200) = 2^8 = 256
        *
        * The bit is now at position 8 relative to its group.
        *
        * B. DIV
        *
        *     div(0xd76453e0, remainingValue)
        *
        * Divides the carefully selected constant by the remaining isolated bit.
        *
        * This produces a value used to select the correct entry in the second lookup table.
        *
        * C. AND(0x1f, ...)
        *
        *     and(0x1f, divisionResult)
        *
        * The value 0x1f is:
        *
        *     Binary: 00011111
        *
        * It keeps only the lowest 5 bits of the division result.
        *
        * This produces a lookup index between 0 and 31.
        *
        * D. BYTE
        *
        *     byte(lookupIndex, lookupTable)
        *
        * Extracts the byte at the selected index from the
        * 32-byte lookup table.
        *
        * The table has been arranged so that the selected byte contains the exact
        * position of the isolated bit within its group of 32.
        *
        * This gives us the lower 5 bits of the original index.
        *
        * E. OR
        *
        *     or(r, lookupResult)
        *
        * Combines the upper portion already stored in r with
        * the lower 5 bits returned by the lookup.
        *
        * These portions occupy different bit positions, so
        * bitwise OR combines them without overlapping.
        *
        * The result is the original zero-based bit position.
        *
        *
        * EXAMPLE 1: x = 40
        *
        * Our original number is:
        *
        *     x = 40
        *
        *     Binary: 00101000
        *
        * Its rightmost set bit is at index 3.
        *
        * FIRST STEP: ISOLATE THE RIGHTMOST SET BIT
        *
        *     x := and(x, sub(0, x))
        *
        *     x & -x = 8
        *
        * So x is now:
        *
        *     x = 8
        *
        *     Binary: 00001000
        *
        * SECOND STEP: FIND THE UPPER 3 BITS
        *
        * The isolated bit is at index 3.
        *
        * Since index 3 belongs to group 0 (positions 0 - 31),
        * the first lookup produces:
        *
        *     group = 0
        *
        * Then:
        *
        *     shl(5, 0) = 0
        *
        * Therefore:
        *
        *     r = 0
        *
        * THIRD STEP: FIND THE LOWER 5 BITS
        *
        * We now evaluate:
        *
        *     shr(r, x)
        *
        * Since r = 0:
        *
        *     shr(0, 8) = 8
        *
        * Now divide the second lookup constant by 8:
        *
        *     div(0xd76453e0, 8) = 0x0d76453
        *
        * Apply the mask:
        *
        *     and(0x1f, 0x0d76453) = 28
        *
        * Therefore, the lookup index is 28.
        *
        * The byte at index 28 in the lookup table is:
        *
        *     3
        *
        * This is the position of the isolated bit within its group of 32.
        *
        * Finally:
        *
        *     or(0, 3) = 3
        *
        * RESULT:
        *
        *     leastSignificantBit(40) = 3
        *
        *
        * EXAMPLE 2: x = 2^200
        *
        * Our goal is to find the position of the only set bit.
        *
        * Since x contains only one set bit, isolating it does not change the value:
        *
        *     x & -x = 2^200
        *
        * The isolated bit is still at index 200.
        *
        *
        * FIRST LOOKUP: FIND THE GROUP
        *
        * The 256 positions are divided into groups of 32.
        *
        * Position 200 belongs to:
        *
        *     Group 6: positions 192 - 223.
        *
        * The first lookup therefore produces:
        *
        *     group = 6
        *
        * We shift this group number left by 5:
        *
        *     shl(5, 6) = 192
        *
        * Therefore:
        *
        *     r = 192
        *
        * What have we established?
        *
        * The isolated bit is within the original range of positions 192 through 223.
        *
        * The offset 192 is now stored in r.
        *
        *
        * SECOND LOOKUP: FIND THE EXACT POSITION WITHIN THE GROUP
        *
        * We now evaluate:
        *
        *     shr(r, x)
        *
        * Since:
        *
        *     r = 192
        *     x = 2^200
        *
        * We get:
        *
        *     shr(192, 2^200) = 2^8 = 256
        *
        * The original bit was at position 200.
        * We have shifted it right by 192 positions.
        *
        * Therefore, its remaining position is:
        *
        *     200 - 192 = 8
        *
        * Now divide the second lookup constant by 256:
        *
        *     div(0xd76453e0, 256) = 0x0d76453
        *
        * Apply the 5-bit mask:
        *
        *     and(0x1f, 0x0d76453) = 19
        *
        * The lookup index is 19.
        *
        * The byte at index 19 in the lookup table is:
        *
        *     8
        *
        * This tells us that the isolated bit is at position 8
        * within its group of 32.
        *
        * Finally, combine the two portions:
        *
        *     or(192, 8)
        *
        * In binary:
        *
        *     192 = 11000000
        *       8 = 00001000
        *            --------
        *      OR = 11001000 = 200
        *
        * RESULT:
        *
        *     leastSignificantBit(2^200) = 200
        *
        *
        * Therefore: The first lookup finds the group of 32 containing the isolated bit.
        * The second lookup finds the exact position within that group.
        * The two results are combined to recover the original zero-based bit position.
        */
}
