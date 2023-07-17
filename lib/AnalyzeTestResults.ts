import {readFileSync} from 'fs';
import {join} from 'path';
import {XMLParser} from 'fast-xml-parser';

import { ActionInput } from './GetCliArgs.js';

function analyzeTestResults(input: Readonly<ActionInput>) {
  const {resultOutputFile, projectPath, assertCheck, minimumPass, maxFails} = input;
  const resultPath = join(
      projectPath,
      resultOutputFile,
  );

  const testResults = readFileSync(resultPath);
  if (!testResults) {
    throw {msg: 'No test results found: results file is empty'};
  };

  const parser = new XMLParser({ignoreAttributes: false});
  const testResultsObj = parser.parse(testResults.toString());

  // if there were not test suites to run, throw an error
  if (!testResultsObj?.testsuites?.testsuite) {
    throw {msg: 'No test results found'};
  };

  let testCount = 0;
  let failCount = 0;

  if (assertCheck) {
    const testsuites = testResultsObj.testsuites;
    let testSuiteObjects = testsuites.testsuite;

    // if there is only one test suite, it will be an object
    // if there are multiple test suites, they will be an array of objects

    // if there is only one test suite, convert it to an array
    if (!Array.isArray(testSuiteObjects)) {
      testSuiteObjects = [testSuiteObjects];
    };

    testSuiteObjects.forEach((suiteObject) => {
      let {testcase: testCaseObjects} = suiteObject;

      // if there are no test cases in this suite, skip it
      // <testsuite></testsuite>
      if (testCaseObjects === undefined) return;

      // if there is only one test case, it will be an object
      // if there are multiple test cases, they will be an array of objects

      // if there is only one test case, convert it to an array
      if (!Array.isArray(testCaseObjects)) {
        testCaseObjects = [testCaseObjects];
      };

      testCaseObjects.forEach((caseObj) => {
        // this is the <testcase> object, nested under testsuites>testsuite
        // the test case contains the number of assertions and a child node
        // <failure> if the test failed
        const caseAssertions = parseInt(caseObj['@_assertions']);
        testCount += caseAssertions;

        const caseFailed = caseObj.failure;
        if (caseFailed) failCount++;
      });
    });
  } else {
    // this is the root level <testsuites> object
    // the test count and fail count are attributes of this object
    testCount = parseInt(testResultsObj.testsuites['@_tests']);
    failCount = parseInt(testResultsObj.testsuites['@_failures']);
  }

  const passRate = (testCount - failCount) / testCount;

  let success = false;
  const meetsPassRate = passRate >= minimumPass;
  let meetsMaxFails = true;
  if (maxFails) {
    meetsMaxFails = failCount <= maxFails;
  }

  if (meetsPassRate && meetsMaxFails) {
    success = true;
  };

  return {
    testCount,
    failCount,
    passRate,
    success,
  };
};

export default analyzeTestResults;
