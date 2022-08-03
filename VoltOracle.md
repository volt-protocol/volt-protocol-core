# Volt System Oracle

The Volt System Oracle is an oracle that tracks the yield earned in the underlying venues of PCV, and then passes that yield on to Volt holders by setting a rate and increasing the Volt target price.

## Volt Oracle Architecture

The Volt System Oracle sits behind an Oracle Pass Through contract that the time-lock owns. This allows for a changing out of the underlying PCV venues in which the Volt System Oracle points to. A change will occur "at-will" given significant enough deviation of the rates.

The following is the Volt System Oracle Formula where p equals price at the start of the period, p<sub>1</sub> equals new price after all changes are applied, and t equals time.

$$
\begin{align*}
Δt &= min(currentTimestamp - startTime, compoundingPeriod) \\
Δp &= p \cdot \frac{interestRate}{10,000} \\
p_{1} &= p + (\frac{Δp \cdot Δt}{compoundingPeriod})
\end{align*}
$$

Compounding period for the Volt System Oracle is 30.42 days and does not take leap years into account.

Interest accrues per second as long as block.timestamp is greater than start time. After the period is over, the function `compoundInterest` can be called, which sets the start time to the previous start time plus the period length. This means that if a previous period had not been compounded, `compoundInterest` can be called multiple times to catch the oracle price up to where it should be. Interest will not be factored into the current price if `compoundInterest` is not called after the period ends. This is expected behavior as this contract is meant to be as simple as possible.
