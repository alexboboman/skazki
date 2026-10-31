import https from "node:https";

export interface JsonResponse {
  ok: boolean;
  status: number;
  rawBody: string;
}

export function postJson(url: string, headers: Record<string, string>, body: unknown): Promise<JsonResponse> {
  return new Promise((resolve, reject) => {
    const requestBody = JSON.stringify(body);

    const req = https.request(
      url,
      {
        method: "POST",
        headers: {
          ...headers,
          "content-length": Buffer.byteLength(requestBody).toString()
        }
      },
      (res) => {
        let rawBody = "";

        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          rawBody += chunk;
        });
        res.on("end", () => {
          resolve({
            ok: (res.statusCode ?? 500) >= 200 && (res.statusCode ?? 500) < 300,
            status: res.statusCode ?? 500,
            rawBody
          });
        });
      }
    );

    req.on("error", reject);
    req.write(requestBody);
    req.end();
  });
}
