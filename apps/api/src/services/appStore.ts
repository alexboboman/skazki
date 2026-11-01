import { createPublicKey, verify, X509Certificate } from "node:crypto";

/**
 * Apple Root CA - G3, the root of every JWS signed by the App Store (transactions, renewal info and
 * Server Notifications v2). Public certificate, SHA-256 63:34:3A:BF:...:3E:91:79, valid until 2039.
 * Source: https://www.apple.com/certificateauthority/
 */
export const APPLE_ROOT_CA_G3 = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

/** DER encodings of the Apple marker extensions: 1.2.840.113635.100.6.11.1 (leaf) and 1.2.840.113635.100.6.2.1 (intermediate). */
const LEAF_MARKER_OID = Buffer.from("060a2a864886f76364060b01", "hex");
const INTERMEDIATE_MARKER_OID = Buffer.from("060a2a864886f76364060201", "hex");

export interface AppStoreVerifier {
  /** Checks the signature and the certificate chain of an App Store JWS and returns its payload. Throws when it is not genuine. */
  verify<T extends object>(jws: string): T;
}

export interface AppStoreVerifierOptions {
  /** Trusted roots as PEM. Only tests replace the default (Apple Root CA - G3). */
  rootCertificates?: string[];
  /** Whether leaf and intermediate must carry Apple's marker extensions (a developer certificate from the same root must not pass). Tests turn it off. */
  requireAppleExtensions?: boolean;
}

export function createAppStoreVerifier(options: AppStoreVerifierOptions = {}): AppStoreVerifier {
  const roots = (options.rootCertificates ?? [APPLE_ROOT_CA_G3]).map((pem) => new X509Certificate(pem));
  const requireExtensions = options.requireAppleExtensions ?? true;

  return {
    verify<T extends object>(jws: string): T {
      const parts = jws.split(".");

      if (parts.length !== 3) {
        throw new Error("Not a JWS.");
      }

      const [encodedHeader, encodedPayload, encodedSignature] = parts;
      const header = JSON.parse(Buffer.from(encodedHeader, "base64url").toString("utf8"));
      const payload = JSON.parse(Buffer.from(encodedPayload, "base64url").toString("utf8"));

      if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) {
        throw new Error("Unexpected JWS header.");
      }

      const [leaf, intermediate, root] = (header.x5c as unknown[]).map((cert) => {
        if (typeof cert !== "string") {
          throw new Error("Bad certificate in x5c.");
        }
        return new X509Certificate(Buffer.from(cert, "base64"));
      });

      // The chain is checked at the time the data was signed: the leaf certificate is renewed regularly.
      const effective = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : new Date();

      if (!roots.some((trusted) => trusted.fingerprint256 === root.fingerprint256)) {
        throw new Error("Untrusted root certificate.");
      }

      if (!leaf.verify(intermediate.publicKey) || !intermediate.verify(root.publicKey) || !root.verify(root.publicKey)) {
        throw new Error("Broken certificate chain.");
      }

      for (const cert of [leaf, intermediate, root]) {
        if (effective < new Date(cert.validFrom) || effective > new Date(cert.validTo)) {
          throw new Error("Certificate is not valid at the signing time.");
        }
      }

      if (requireExtensions && (!leaf.raw.includes(LEAF_MARKER_OID) || !intermediate.raw.includes(INTERMEDIATE_MARKER_OID))) {
        throw new Error("Certificate is not issued for App Store signing.");
      }

      const signed = verify(
        "sha256",
        Buffer.from(`${encodedHeader}.${encodedPayload}`),
        { key: createPublicKey(leaf.publicKey.export({ type: "spki", format: "pem" })), dsaEncoding: "ieee-p1363" },
        Buffer.from(encodedSignature, "base64url")
      );

      if (!signed) {
        throw new Error("Bad JWS signature.");
      }

      return payload as T;
    }
  };
}

// --- Payloads (only the fields we read) ---

/** JWSTransactionDecodedPayload. Dates are milliseconds since the epoch. */
export interface TransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  type?: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: "Sandbox" | "Production" | string;
  signedDate?: number;
}

/** JWSRenewalInfoDecodedPayload. */
export interface RenewalInfo {
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
  signedDate?: number;
}

/** ResponseBodyV2DecodedPayload: the signed payload of a Server Notification v2. */
export interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  signedDate?: number;
  data?: {
    environment?: string;
    bundleId?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}
