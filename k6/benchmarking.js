  import http from 'k6/http';
  import { check } from 'k6';

  export const options = {
    stages: [
      { duration: '1m', target: 50 },   // Ramp to 50 users
      { duration: '2m', target: 100 },  // Ramp to 100 users
      { duration: '2m', target: 200 },  // Ramp to 200 users
      { duration: '1m', target: 0 },    // Ramp down
    ],
  };

  export default function () {
    const res = http.get('http://localhost:30090/health');

    check(res, {
      'status is 200': (r) => r.status === 200,
    });
  }

