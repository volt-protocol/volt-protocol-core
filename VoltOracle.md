# Volt System Oracle

The Volt System Oracle is an oracle that tracks the yield earned in the underlying venues of PCV, and then passes that yield on to Volt holders by setting a rate and increasing the Volt target price.

## Volt Oracle Architecture

The Volt System Oracle will sit behind an Oracle Pass Through contract that the timelock owns, so that the Volt System Oracle the Oracl Pass Through points to can be changed out at will should rates in the underlying PCV venues change.

The following is the Volt System Oracle Formula where p equals price and t equals time.

Δt = min{current timestamp - start time, compounding period}

Δp = p * interest rate (basis points) / 10,000

p = Δp * Δt / compounding period + p

Compounding period for the Volt System Oracle is 1 year and does not take leap years into account. 

Interest accrues per second as long as block.timestamp is greater than start time. After the period is over, the function `compoundInterest` can be called, which sets the start time to the previous start time plus the period length. This means that if a previous period had not been compounded, `compoundInterest` can be called multiple times to catch the oracle price up to where it should be. Interest will not be factored into the current price if `compoundInterest` is not called after the period ends. This is expected behavior as this contract is meant to be as minified and simple as possible.
