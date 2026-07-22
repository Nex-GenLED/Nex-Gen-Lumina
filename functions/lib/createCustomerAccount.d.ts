/**
 * createCustomerAccount — Firebase Cloud Function (callable)
 *
 * Creates the customer-facing Firebase Auth user during the Day 2
 * wrap-up flow. Replaces the client-side stub the wrap-up screen has
 * been calling against — see day2_wrap_up_screen.dart Step 3 for the
 * caller, and the Prompt 7 build report for the contract.
 *
 * Idempotent: if a user already exists for the supplied email, returns
 * that user's uid with tempPasswordSent=false. The wrap-up screen
 * already handles this case.
 *
 * Side effects on success:
 *   • Creates the auth user (admin.auth().createUser)
 *   • Generates a password reset link (admin.auth().generatePasswordResetLink)
 *   • Sends a welcome email via Resend with the reset link + store links
 *   • Seeds /users/{uid} with displayName, email, dealerCode, jobId,
 *     installation_role: 'primary'
 *
 * NOTE: this function does NOT call SalesJobService.linkToInstall to
 * write the new uid back onto the SalesJob — that's the wrap-up
 * screen's job (it calls setLinkedUserId after this returns).
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:createCustomerAccount
 */
interface CreateCustomerAccountResult {
    uid: string;
    tempPasswordSent: boolean;
}
export declare const createCustomerAccount: import("firebase-functions/v2/https").CallableFunction<any, Promise<CreateCustomerAccountResult>, unknown>;
export {};
