# Volt Improvement Proposal 2

This VIP aims to add all EOA's as guardians across both Arbitrum and Ethereum, swap out the CPI-U oracle with a new Volt System Oracle, reduce mint and burn fees on all PSMs, and revoke the proposer role from a deprecated account.

## Known Contract Limitations

Currently the new Volt System Oracle uses linear interpolation to calculate price increases from the start of the period till the end of the period. This means that interest does not compound until the end of the period, so if purchased during the middle of a period, a user will not earn interest for the part of their deposit that purchased interest until the next period.

If the current block timestamp is past the periodStart + timeframe, and `compoundInterest` has not been called, then interest will not accrue which could cause issues if users are able to buy Volt at a non updated price, call compoundInterest, and then sell the Volt back to the protocol at a higher price. However, this is a known issue and will be mitigated by creating keepers which trigger the compounding just after the period ends to minimize the impact of this issue.

Overflows can cause reverts in getCurrentOraclePrice if the oraclePrice is too large. This would take approximately ~6,000 years to become an issue at current interest rates.

The timeframe set in the Volt Oracle was chosen at 30.42 days, which is 0.04 days longer than 1 year, this was intentional and done for readability as the correct timeframe would be 365.25 days. However, a shorter timespan was chosen to address the compound interest issue.

Leap years are not accounted for in this oracle because we are not in a leap year, and this oracle is a temporary solution until Volt 2.0 ships.

monthlyChangeRateBasisPoints is an immutable value set at construction time, and yields in underlying venues can fluctuate. If rates in underlying venues diverge too much from monthlyChangeRateBasisPoints, a new VoltSystemOracle can be deployed which has an updated rate.

monthlyChangeRateBasisPoints might not allow full expressivity of rates in underlying venues due to its limitation of being between 1 and 10,000 and not allowing for yields smaller than 0.01% monthly.
