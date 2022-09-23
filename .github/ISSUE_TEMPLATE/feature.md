---
name: Feature
about: ''
title: ''
labels: ''
assignees: ''

---

**Feature Description**
A clear description of your feature, the problem it solves, and how it solves the problem.

**Testing**
 -[ ] Unit Testing
 -[ ] Integration Testing
 -[ ] Fuzz Testing
 -[ ] Governance Simulation Framework

**Security Checklist**
 -[ ] No Reentrancy possible
 -[ ] Check-Effects-Interaction pattern is followed
 -[ ] Look at areas that interface with external contracts and ensure all assumptions about them are valid like share price only increases, etc.
 -[ ] Do a generic line-by-line review of the contracts.
 -[ ] Do another review from the perspective of every actor in the threat model.
 -[ ] Glance over the project's tests + code coverage and look deeper at areas lacking coverage.
 -[ ] Run tools like Slither/Solhint and review their output.
 -[ ] Look at related projects and their audits to check for any similar issues or oversights.
 -[ ] Create a threat model and make a list of theoretical high level attack vectors.
 Write negative tests. E.g., if users should NOT be able to withdraw within 100 blocks of depositing, then write a test where a users tries to withdraw early and make sure the user's attempt fails.
 -[ ] Write down your security assumptions. This doesn't have to be super formal. E.g., "We assume that the owner is not malicious, that the Chainlink oracles won't lie about the token price, that the Chainlink oracles will always report the price at least once every 24 hours, that all tokens that the owner approves are ERC20-compliant tokens with no transfer hooks, and that there will never be a chain reorg of more than 30 blocks". This helps you understand how things could possibly go wrong even if your contracts are bug-free. Auditors may also be able to tell you whether or not your assumptions are realistic. They may also be able point out assumptions you're making that you didn't realize you were making.
 -[ ] Areas of concern for review were found to be secure
 -[ ] Any public function that can be made external should be made external. This is not just a gas consideration, but it also reduces the cognitive overhead for auditors because it reduces the number of possible contexts in which the function can be called.
 -[ ] Use the latest major version of Solidity.

**Audit Log**
