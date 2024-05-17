module.exports = {
  skipFiles: ['test', 'openzeppelin', 'relay', 'tools', 'solady'],
  configureYulOptimizer: true,
  mocha: {
    grep: "@skip-on-coverage", // Find everything with this tag
    invert: true               // Run the grep's inverse set.
  },
  solcOptimizerDetails: {
    peephole: false,
    //inliner: false,
    jumpdestRemover: false,
    orderLiterals: false,  // <-- TRUE! Stack too deep when false
    deduplicate: false,
    cse: false,
    constantOptimizer: false,
    yul: false,
  }
};
