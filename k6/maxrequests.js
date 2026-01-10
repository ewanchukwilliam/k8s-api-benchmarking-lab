  import http from 'k6/http';
  import { check, sleep } from 'k6';


  const num = 1000;
  export const options = {
    stages: [
      // { duration: '10s', target: num/5 },   // Ramp to 20 users
      { duration: '10s', target: 0 },    
      { duration: '30s', target: num },    
      { duration: '5m', target: num },   
      { duration: '30s', target: 0 },    
    ],
  };

  export default function () {
    const res = http.get('http://a09cc957f43ec4154bc745f9def963c6-5e285582f5c1f062.elb.us-east-1.amazonaws.com/health');

    check(res, {
      'status is 200': (r) => r.status === 200,
      // 'response time < 100ms': (r) => r.timings.duration < 100,
    });

    // Uncomment to add delay and measure steady-state throughput
    // sleep(0.1);  // 100ms think time = ~10 requests/second per user
  }

 // this means 10k requests per second holds comfortably at 9 pods with 0.5 cpu cores  
// cool beans not running into issues of request port maxxing now. 1000 conccurrent users spamming my docker instance conncurrently is 10k requests per second for 9 cores aka 9 containers then stabilizes at 64% usage. 
  // AKA THIS IS SO FUCKING COOL
  // only drops requests during ramp up. then drops less and less often. 
