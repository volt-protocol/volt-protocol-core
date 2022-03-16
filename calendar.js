/// Proof that we don't need to use the solidity calendar
const secondsPerDay = 86400;
const averageDaysPerMonthLeapYear = 30.5;
const averageDaysPerMonthNonLeapYear = 30.4166666666;
const scale = 1000;
const secondsPerYear = Math.floor(secondsPerDay * 365);
const secondsPerLeapYear = Math.floor(secondsPerDay * 366);

/// source: https://stackoverflow.com/a/6078873
function timeConverter(UNIX_timestamp) {
  var a = new Date(UNIX_timestamp);
  var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var year = a.getFullYear();
  var month = months[a.getMonth()];
  var date = Number(a.getDate());
  var time = date + 'th ' + month + ' ' + year;
  return time;
}

/// list all days in a year
function getListOfDates(startingTime, daysPerMonth) {
  const allDates = [];

  for (let i = 1; i <= 12; i++) {
    const secondsDelta = Math.ceil(secondsPerDay * i * daysPerMonth);
    const newDate = new Date(Math.floor(startingTime + secondsDelta) * scale);

    allDates.push(newDate);
  }

  return allDates;
}

function main() {
  const startingTime = 1647381554 + secondsPerDay * 2;

  for (let i = 0; i < 4; i++) {
    const yearDelta = secondsPerYear * i;
    const unixtime = startingTime + yearDelta;
    const currentYear = new Date(unixtime * scale);

    const isCurrentTimeLeapYear = currentYear.getFullYear() % 4 === 0;
    const dates = getListOfDates(
      isCurrentTimeLeapYear ? startingTime + secondsPerLeapYear * i : startingTime + secondsPerYear * i,
      isCurrentTimeLeapYear ? averageDaysPerMonthLeapYear : averageDaysPerMonthNonLeapYear
    );

    console.log(`----------- Year ${currentYear.getFullYear()} -----------`);
    dates.forEach((date) => {
      console.log(timeConverter(date));
    });
  }
}

main();
