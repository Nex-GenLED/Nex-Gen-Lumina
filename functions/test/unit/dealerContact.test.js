/**
 * dealerContact — the dealer contact denormalised onto customer profiles
 * (+110, package G follow-up 4). Pure helpers plus the two-step lookup.
 */

const {
  dealerContactFromRecord,
  dealerContactFields,
  lookupDealerContact,
} = require("../../lib/dealerContact");

/** Fake /dealers: documents keyed by id, each carrying its own fields. */
function makeDb(docsById) {
  return {
    collection(path) {
      if (path !== "dealers") throw new Error(`unexpected collection ${path}`);
      return {
        doc(id) {
          return {
            async get() {
              const d = docsById[id];
              return { exists: d !== undefined, data: () => d };
            },
          };
        },
        where(field, op, value) {
          return {
            limit() {
              return {
                async get() {
                  const hits = Object.values(docsById).filter(
                    (d) => d && d[field] === value,
                  );
                  return { empty: hits.length === 0, docs: hits.map((d) => ({ data: () => d })) };
                },
              };
            },
          };
        },
      };
    },
  };
}

describe("dealerContactFromRecord", () => {
  it("prefers companyName, then businessName, then name; lower-cases email", () => {
    expect(
      dealerContactFromRecord({
        name: "Pat",
        companyName: "Bright Homes LED",
        phone: " (555) 010-0100 ",
        email: "Hello@Example.com",
      }),
    ).toEqual({ name: "Bright Homes LED", phone: "(555) 010-0100", email: "hello@example.com" });
    expect(dealerContactFromRecord({ businessName: "B", name: "N" })).toEqual({
      name: "B",
      phone: undefined,
      email: undefined,
    });
  });

  it("is undefined for a missing or empty record", () => {
    expect(dealerContactFromRecord(undefined)).toBeUndefined();
    expect(dealerContactFromRecord({ phone: "  ", email: "" })).toBeUndefined();
  });
});

describe("dealerContactFields", () => {
  it("writes only the values that exist, under the profile's snake_case keys", () => {
    expect(dealerContactFields({ name: "B", phone: "1" })).toEqual({
      dealer_name: "B",
      dealer_phone: "1",
    });
    expect(dealerContactFields(undefined)).toEqual({});
    // A record with a name but no phone or email never blanks anything.
    expect(Object.keys(dealerContactFields({ name: "Only Name" }))).toEqual(["dealer_name"]);
  });
});

describe("lookupDealerContact", () => {
  const record = { dealerCode: "01", companyName: "Bright Homes LED", phone: "555", email: "h@example.com" };

  it("finds a record keyed by its code", async () => {
    const c = await lookupDealerContact(makeDb({ "01": record }), "01");
    expect(c.name).toBe("Bright Homes LED");
  });

  it("falls back to the dealerCode field when the record is keyed otherwise (the live mismatch)", async () => {
    const c = await lookupDealerContact(makeDb({ NXG_something: record }), "01");
    expect(c.phone).toBe("555");
  });

  it("is undefined for an unknown code, a blank code, or a failing store", async () => {
    expect(await lookupDealerContact(makeDb({}), "99")).toBeUndefined();
    expect(await lookupDealerContact(makeDb({}), "  ")).toBeUndefined();
    const broken = { collection() { throw new Error("permission-denied"); } };
    expect(await lookupDealerContact(broken, "01")).toBeUndefined();
  });
});
