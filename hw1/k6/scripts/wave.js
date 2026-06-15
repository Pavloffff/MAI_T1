import { trafficMix } from './common.js';

// Сценарий "Волна": плавное нарастание 0 to 500 VU за 2 минуты
export const options = {
  scenarios: {
    wave: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 500 },
        { duration: '2m', target: 500 },
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1500'],
  },
};

export default function () {
  trafficMix();
}
