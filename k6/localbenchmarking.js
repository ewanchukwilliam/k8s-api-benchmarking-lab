import http from 'k6/http';
import { check, sleep } from 'k6';

const num = 2000;
export const options = {
  stages: [
    { duration: '15s', target: num },
    { duration: '5m', target: num },
    { duration: '10s', target: 0 },
  ],
};

export default function () {
  const res = http.get('http://localhost/ping');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.00001);
}
