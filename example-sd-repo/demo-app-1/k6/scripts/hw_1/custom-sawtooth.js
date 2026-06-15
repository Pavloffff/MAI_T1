import http from 'k6/http';
import { check, sleep } from 'k6';
import { API_DIRECT_URL, BASE_URL, orderPayload } from './common.js';

// Сценарий "Пила" (модификация): чередование write-heavy и read-heavy фаз.
// Цель - проверить, как система ведёт себя при смене профиля нагрузки
// (INSERT-нагрузка на БД vs SELECT через Nginx).
export const options = {
  scenarios: {
    sawtooth: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 200 },
        { duration: '30s', target: 50 },
        { duration: '30s', target: 300 },
        { duration: '30s', target: 50 },
        { duration: '30s', target: 0 },
      ],
    },
  },
};

let iteration = 0;

export default function () {
  iteration++;
  const writeHeavyPhase = Math.floor(iteration / 100) % 2 === 0;

  if (writeHeavyPhase) {
    // 95% POST - имитация всплеска оформления заказов
    const res = http.post(`${API_DIRECT_URL}/api/orders`, orderPayload(), {
      headers: { 'Content-Type': 'application/json' },
    });
    check(res, { 'write phase ok': (r) => r.status < 500 });
  } else {
    // 95% GET - имитация просмотра каталога через reverse proxy
    const res = http.get(`${BASE_URL}/api/orders`);
    check(res, { 'read phase ok': (r) => r.status === 200 });
  }
  sleep(0.03);
}
