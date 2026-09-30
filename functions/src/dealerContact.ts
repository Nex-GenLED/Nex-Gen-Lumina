/**
 * dealerContact — the dealer contact fields denormalised onto a customer's
 * profile at provisioning (+110, package G follow-up 4).
 *
 * Customers cannot read /dealers (firestore.rules), so the link-account
 * screen shows the dealer's card only from these profile fields:
 *   dealer_name, dealer_phone, dealer_email
 * Written by createCustomerAccount and claimCustomerByEmail here, and by the
 * installer wizard on the client. Only non-empty values are written, so an
 * incomplete dealer record never blanks a value already on the profile.
 *
 * Lookup order: the document keyed by the code (the shape
 * CorporateAdminService.createDealer writes), then a query on the
 * `dealerCode` field, because the two live dealer records are not keyed by
 * their code (the "dealer 01 id mismatch"). Both are Admin-SDK reads.
 */

export interface DealerContact {
  name?: string;
  phone?: string;
  email?: string;
}

/** The profile keys, as UserModel.fromJson reads them. */
export interface DealerContactFields {
  dealer_name?: string;
  dealer_phone?: string;
  dealer_email?: string;
}

function nonEmpty(v: unknown): string | undefined {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
}

/** Pure: a dealer record's contact, or undefined when it has none. */
export function dealerContactFromRecord(
  data: Record<string, unknown> | undefined,
): DealerContact | undefined {
  if (!data) return undefined;
  const contact: DealerContact = {
    name:
      nonEmpty(data.companyName) ??
      nonEmpty(data.businessName) ??
      nonEmpty(data.name),
    phone: nonEmpty(data.phone),
    email: nonEmpty(data.email)?.toLowerCase(),
  };
  if (!contact.name && !contact.phone && !contact.email) return undefined;
  return contact;
}

/** Pure: the profile fields to merge; only the values that exist. */
export function dealerContactFields(
  contact: DealerContact | undefined,
): DealerContactFields {
  if (!contact) return {};
  const out: DealerContactFields = {};
  if (contact.name) out.dealer_name = contact.name;
  if (contact.phone) out.dealer_phone = contact.phone;
  if (contact.email) out.dealer_email = contact.email;
  return out;
}

/** The slice of Firestore the lookup needs, so tests can fake it. */
export interface DealerLookupDb {
  collection(path: string): {
    doc(id: string): {
      get(): Promise<{
        exists: boolean;
        data(): Record<string, unknown> | undefined;
      }>;
    };
    where(
      field: string,
      op: "==",
      value: string,
    ): {
      limit(n: number): {
        get(): Promise<{
          empty: boolean;
          docs: Array<{ data(): Record<string, unknown> | undefined }>;
        }>;
      };
    };
  };
}

/**
 * Finds the dealer record for [dealerCode]: by document id first, then by
 * the `dealerCode` field. Never throws; a failed read means no contact.
 */
export async function lookupDealerContact(
  db: DealerLookupDb,
  dealerCode: string,
): Promise<DealerContact | undefined> {
  const code = dealerCode.trim();
  if (!code) return undefined;
  try {
    const byId = await db.collection("dealers").doc(code).get();
    if (byId.exists) {
      const c = dealerContactFromRecord(byId.data());
      if (c) return c;
    }
    const byField = await db
      .collection("dealers")
      .where("dealerCode", "==", code)
      .limit(1)
      .get();
    if (!byField.empty) return dealerContactFromRecord(byField.docs[0].data());
  } catch {
    // Best effort: the profile still gets its role and dealer_code.
  }
  return undefined;
}
