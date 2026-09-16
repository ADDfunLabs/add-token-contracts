# FullMath attribution

`contracts/FullMath.sol` adapts the MIT-licensed Uniswap v3-core FullMath algorithm credited to Remco Bloemen. Reference: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol and https://xn--2-umb.com/21/muldiv .

Local changes: Solidity 0.8.20 pragma, explicit unchecked modular arithmetic, named errors, concise comments and names, ceiling function renamed mulDivUp. This local adaptation and its integration require review; no upstream audit assurance is transferred to ADD. The source package freezes the actual adapted file by SHA-256. FullMathHarness is a local test contract and is not part of production deployment.

## MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Local ERC20 and utilities

The contracts/openzeppelin/ files explicitly identify themselves as local implementations. Directory naming and compatible APIs do not establish upstream provenance, version equivalence or audit coverage. Their original SPDX identifiers and comments are preserved.

Existing MIT SPDX identifiers apply to the published Solidity files. Original authors retain their rights; the ADD copyright notice applies to ADD contributions. This publication includes neither third-party endorsement nor an independent audit certification.
