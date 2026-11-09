import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.1/index.js";

export const options = {
  scenarios: {
    todo_kafka_flow: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '10s', target: 5 },
        { duration: '20s', target: 10 },
        { duration: '5s', target: 0 },
      ],
      gracefulRampDown: '5s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],   // Under 5% errors
    http_req_duration: ['p(95)<300'], // 95% of requests under 300ms
  },
};

const BASE_URL = 'http://localhost:3000';

export default function () {
  const vuId = exec.vu.idInTest;
  const iter = exec.scenario.iterationInTest;
  const email = `k6_user_${vuId}_${iter}_${Date.now()}@example.com`;
  const password = 'Password123!';

  // 1. Register User
  const regPayload = JSON.stringify({ email: email, password: password });
  const regRes = http.post(`${BASE_URL}/auth/register`, regPayload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(regRes, {
    'registered (201)': (r) => r.status === 201,
  });

  // 2. Login to obtain JWT
  const loginPayload = JSON.stringify({ email: email, password: password });
  const loginRes = http.post(`${BASE_URL}/auth/login`, loginPayload, {
    headers: { 'Content-Type': 'application/json' },
  });

  const loginSuccess = check(loginRes, {
    'logged in (200)': (r) => r.status === 200,
  });

  if (!loginSuccess) {
    return;
  }

  const token = loginRes.json('token');
  const authHeaders = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  };

  // 3. Create Todo (Dispatches Kafka Event asynchronously)
  const todoPayload = JSON.stringify({
    title: `Task for VU ${vuId} Iteration ${iter}`,
    completed: false,
  });

  const todoRes = http.post(`${BASE_URL}/todos`, todoPayload, {
    headers: authHeaders,
  });

  check(todoRes, {
    'todo created & event fired (201)': (r) => r.status === 201,
  });

  sleep(0.5);
}

// Generate styled UI report
export function handleSummary(data) {
  return {
    "stdout": textSummary(data, { indent: " ", enableColors: true }),
    "test-results.html": htmlReport(data),
  };
}
