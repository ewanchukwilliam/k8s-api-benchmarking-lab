  import http from 'k6/http';
  import { check, sleep } from 'k6';

  export const options = {
    stages: [
      { duration: '3m', target: 400 },  // Ramp to 200 users
      { duration: '5m', target: 1500 },  // Ramp to 200 users
      { duration: '1m', target: 0 },    // Ramp down
    ],
  };

  export default function () {
    const res = http.get('http://api.codeseeker.dev/health');

    check(res, {
      'status is 200': (r) => r.status === 200,
    });
	sleep(0.0001);  // 100ms think time = ~10 requests/second per user
  }

