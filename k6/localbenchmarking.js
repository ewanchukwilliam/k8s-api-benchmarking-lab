import http from 'k6/http';
import { check, sleep } from 'k6';

const num = 1500;
export const options = {
  stages: [
    { duration: '15s', target: num },
    { duration: '5m', target: num },
    { duration: '10s', target: 0 },
  ],
};

export default function () {
  const res = http.get('http://localhost/health');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

}
