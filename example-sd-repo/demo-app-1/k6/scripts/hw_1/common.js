import http from 'k6/http';
import { check, sleep } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
export const API_DIRECT_URL = __ENV.API_DIRECT_URL || 'http://localhost:8081';

export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

export function orderPayload() {
  return JSON.stringify({
    user_id: randomInt(1, 2),
    amount: Math.random() * 100,
    description: 'k6 load',
  });
}

export function trafficMix() {
  if (Math.random() < 0.8) {
    const res = http.post(`${API_DIRECT_URL}/api/orders`, orderPayload(), {
      headers: { 'Content-Type': 'application/json' },
      tags: { name: 'POST /api/orders' },
    });
    check(res, {
      'order created': (r) => r.status === 200 || r.status === 201,
    });
  } else {
    const res = http.get(`${BASE_URL}/api/orders`, {
      tags: { name: 'GET /api/orders' },
    });
    check(res, { 'orders listed': (r) => r.status === 200 });
  }
  sleep(0.05);
}
