  import http from 'k6/http';
  import { check } from 'k6';


  const num = 20000
  export const options = {
    stages: [
      { duration: '10s', target: 0 },   
      // { duration: '20s', target: num*2 },  
      { duration: '30s', target: num },
      // { duration: '10s', target: 0 },    
      { duration: '10s', target: 0 },   
    ],
  };

  export default function () {
    const res = http.get('http://localhost:30090/health');

    check(res, {
      'status is 200': (r) => r.status === 200,
    });
  }

