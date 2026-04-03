---
title: "Nex-Gen Lumina — Dealer Dashboard Guide"
subtitle: "How to track your sales pipeline, manage installers, and earn referral rewards"
author: "Nex-Gen LED"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Dealer Dashboard Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #222; line-height: 1.6; }
  h1 { color: #00B8D4; border-bottom: 2px solid #00B8D4; padding-bottom: 8px; }
  h2 { color: #00E5FF; margin-top: 28px; }
  h3 { color: #333; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #00B8D4; color: white; }
  .tip { background: #E0F7FA; border-left: 4px solid #00B8D4; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: #FFF3E0; border-left: 4px solid #FF9800; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #F5F5F5; border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Dealer Dashboard Guide

The Dealer Dashboard is your business command center within the Lumina app. It gives you a real-time view of your entire sales operation — from new prospects to completed installations, installer performance, referral rewards, and payout status. Everything updates live from Firestore, so you always have an accurate picture of where your business stands.

---

## 1. Overview

As a Nex-Gen dealer, the Dealer Dashboard lets you:

- **Track sales jobs** from initial prospect visit through completed installation
- **Monitor your installer team** — see who is active, how many installs they have completed, and what jobs are in progress
- **Manage referral rewards** — track referral codes, see which referrals have converted, and monitor your ambassador tier
- **View payout status** — see pending, approved, and fulfilled payouts for referral rewards

The dashboard pulls data in real time from the Nex-Gen cloud. Every job update, installer change, and payout approval appears immediately.

---

## 2. Accessing the Dealer Dashboard

### From a Sales Session

1. Open the Lumina app
2. Navigate to **Sales Mode** (from the login screen or Settings)
3. Enter your **sales PIN** on the numeric keypad
4. The app authenticates your dealer credentials against Firestore
5. Tap **Dealer Dashboard** to open your business overview

### From an Installer Session

1. Open the Lumina app
2. Navigate to **Installer Mode**
3. Enter your **4-digit installer PIN** (dealer code + installer code)
4. Tap **Dealer Dashboard** from the session menu

### From Admin Access

Nex-Gen administrators can view any dealer's dashboard:

1. Open **Installer Mode** and tap **Admin Access**
2. Enter the admin PIN
3. Navigate to **Manage Dealers** and tap a dealer
4. The dashboard opens in **Admin view** mode (indicated by an amber label)

<div class="tip">
<strong>Tip:</strong> Your dealer code badge (e.g., "Dealer 03") appears in the top-right corner of the dashboard at all times, confirming which dealership you are viewing.
</div>

---

## 3. Dashboard Tabs

The Dealer Dashboard is organized into four tabs:

| Tab | Purpose |
|-----|---------|
| **Overview** | At-a-glance stats, pipeline summary bar, and recent activity feed |
| **Pipeline** | All sales jobs grouped by status — your full sales funnel |
| **Team** | Installer roster with activity and installation counts |
| **Payouts** | Referral reward payouts — pending, approved, and fulfilled |

---

## 4. Overview Tab

The Overview tab is your daily snapshot. It loads automatically when you open the dashboard.

### Stat Cards

Four metric cards appear at the top:

| Card | What It Shows |
|------|--------------|
| **Active Jobs** | Number of jobs that have not yet reached "Install Complete" |
| **Completed** | Total installations completed across your dealership |
| **Installers** | Number of installers registered under your dealer code |
| **Pending Payouts** | Number of referral payouts awaiting Nex-Gen approval |

### Pipeline Status Bar

Below the stat cards, a horizontal bar chart shows the distribution of jobs across each stage of the sales pipeline. This gives you an instant visual of where your jobs are concentrated — for example, a heavy cluster in "Estimate Sent" may signal follow-up is needed.

### Recent Activity Feed

The bottom of the Overview tab displays a chronological feed of your most recent business events (up to 15 entries), including:

- New jobs created
- Estimates sent and signed
- Pre-wire completions
- Installations completed
- Payout requests and approvals

Each activity entry shows a timestamp badge (e.g., "2h ago", "yesterday", "3d ago") and the associated job number and dollar value.

<div class="tip">
<strong>Tip:</strong> Tap <strong>View all</strong> at the bottom of the activity feed to jump directly to the Pipeline tab for the full job list.
</div>

---

## 5. Pipeline Tab — Sales Jobs

The Pipeline tab shows every sales job under your dealership, ordered by most recently updated. Each job displays:

- **Customer name** and address
- **Job number** (e.g., `NXG-0847`)
- **Current status** with a color-coded badge
- **Total price** of the installation
- **Progress bar** showing how far through the pipeline the job has advanced

### Sales Job Statuses

Jobs progress through these stages:

| Status | Description | Progress |
|--------|-------------|----------|
| **Draft** | Job created, prospect information entered | 10% |
| **Estimate Sent** | PDF estimate generated and delivered to customer | 30% |
| **Estimate Signed** | Customer has reviewed and signed the estimate | 50% |
| **Pre-Wire Scheduled** | Day 1 (pre-wire) appointment is booked | 65% |
| **Pre-Wire Complete** | Day 1 work is finished — conduit, wiring, and mounting done | 80% |
| **Install Complete** | Day 2 work is finished — LEDs installed, system tested and handed off | 100% |

### The Full Job Lifecycle

```
Prospect Visit  -->  Zone Survey  -->  Estimate Generated  -->  Customer Signs
   --> Pre-Wire Scheduled  -->  Pre-Wire Complete  -->  Installation Complete
```

Each stage is visible in the dashboard with the date it occurred and the responsible salesperson or installer.

### Viewing Job Details

Tap any job in the pipeline list to see the full detail view, including:

- Prospect contact information (name, email, phone, address)
- Installation zones with product type, run lengths, and pricing
- Power mount and injection point details
- Photos captured during the site visit
- Salesperson notes
- Estimate and signature history

<div class="tip">
<strong>Tip:</strong> Follow up on estimates that have been in "Estimate Sent" for more than a week. The longer an unsigned estimate sits, the less likely it converts.
</div>

---

## 6. Team Tab — Managing Your Installers

The Team tab shows every installer registered under your dealership.

### Installer Information

For each installer, you can see:

| Field | Description |
|-------|-------------|
| **Name** | Installer's full name |
| **PIN** | Their 4-digit PIN (dealer code + installer code) |
| **Status** | Active or inactive |
| **Installations** | Total number of completed customer setups |

### What You Can Do

- **View installer details** — tap any installer to see their full profile
- **Coordinate job assignments** — see who is available and who has jobs in progress
- **Monitor performance** — compare installation counts across your team

<div class="warning">
<strong>Important:</strong> Only Nex-Gen administrators can add, deactivate, or edit installers. If you need to onboard a new technician or deactivate a departed one, contact your Nex-Gen admin team.
</div>

### PIN Format Reminder

Every installer's PIN is built from your dealer code:

```
[Dealer Code (2 digits)] + [Installer Code (2 digits)]
```

**Example:** If your dealer code is `03` and the installer's code is `05`, their PIN is **0305**.

---

## 7. Payouts Tab — Referral Rewards

The Payouts tab tracks all referral reward payouts associated with jobs under your dealership.

### Payout Statuses

| Status | Meaning |
|--------|---------|
| **Pending** | Installation is complete and reward has been calculated, but is awaiting Nex-Gen admin approval |
| **Approved** | Nex-Gen admin has reviewed and approved the payout |
| **Fulfilled** | The reward (gift card or credit) has been issued to the referrer |
| **GC Cap Reached** | The referrer hit their annual Visa gift card limit — credit was issued instead |

### Payout Details

Each payout entry shows:

- **Prospect name** — the customer whose installation triggered the reward
- **Job number** — links back to the sales job
- **Install value** — the total dollar value of the installation
- **Reward amount** — the payout value (based on the reward tier)
- **Reward type** — Visa Gift Card or Nex-Gen Credit
- **Date created** and **date approved** (if applicable)

### The Payout Lifecycle

1. A referred customer's installation reaches **Install Complete**
2. The system automatically calculates the reward based on the installation value and the referral reward tier table
3. A payout record is created with **Pending** status
4. A Nex-Gen administrator reviews and **approves** the payout
5. The reward is issued (**Fulfilled**) — either as a Visa gift card or Nex-Gen credit

---

## 8. Referral Rewards Program

The Lumina referral program rewards customers (and dealers) for bringing in new business. As a dealer, understanding this system helps you promote referrals and answer customer questions.

### How Referrals Work

1. Every Lumina user receives a unique referral code (format: `LUM-XXXX`)
2. When a new prospect mentions a referral code during the sales process, the salesperson enters it on the prospect information form
3. The system tracks the referral through the full sales pipeline
4. When the referred customer's installation is complete, the referrer earns a reward

### Referral Reward Tiers

Rewards are based on the **total installation value** of the referred job:

| Installation Value | Visa Gift Card | Nex-Gen Credit |
|-------------------|----------------|----------------|
| Under $1,500 | $50 | $100 |
| $1,500 -- $2,999 | $100 | $200 |
| $3,000 -- $4,999 | $150 | $300 |
| $5,000 -- $7,499 | $200 | $400 |
| $7,500+ | $250 | $500 |

### Reward Types

Referrers choose between two reward options:

| Type | Description |
|------|-------------|
| **Visa Gift Card** | A physical or digital Visa gift card — capped at **$599 per calendar year** per participant |
| **Nex-Gen Credit** | Credit toward future Nex-Gen equipment or installation — **no annual limit** |

<div class="warning">
<strong>Annual gift card cap:</strong> If a referrer's year-to-date Visa gift card payouts reach $599, subsequent rewards are automatically converted to Nex-Gen Credit at the higher credit rate. The app tracks this automatically — no action is needed from you or the customer.
</div>

### Ambassador Tiers

Referrers progress through ambassador tiers based on their cumulative number of referred installations:

| Tier | Requirement | Color Badge |
|------|------------|-------------|
| **Bronze** | Starting tier (0+ installs) | Amber |
| **Silver** | 3+ referred installations | Silver |
| **Gold** | 8+ referred installations | Gold |
| **Platinum** | 15+ referred installations | Cyan |

Ambassador tier status is displayed on the **Refer & Earn** screen that customers access from Settings. A progress bar shows how close they are to the next tier.

<div class="tip">
<strong>Tip:</strong> Encourage satisfied customers to share their referral code. The more referrals they generate, the higher their ambassador tier climbs — and the more rewarding the program becomes for everyone.
</div>

---

## 9. Understanding Your Sales Data

### Firestore Collections

Your dashboard reads from these cloud collections in real time:

| Collection | Contents |
|------------|----------|
| `sales_jobs` | All sales jobs, filtered by your dealer code |
| `referral_payouts` | Payout records linked to your jobs |
| `installers` | Your installer roster |

### Job Numbers

Every job receives a unique job number (e.g., `NXG-0847`) when created. This number appears throughout the app — on estimates, in the pipeline, on payout records, and in the activity feed. Use it as a universal reference when discussing jobs with your team or with Nex-Gen support.

### Currency and Pricing

All monetary values are displayed in USD. The **total price** on a sales job is the sum of all zone prices within that job. Zone pricing is set during the sales visit based on product type, run length, and installation complexity.

---

## 10. Best Practices

### Daily Routine

- **Check the Overview tab** first thing in the morning for new activity
- **Review the Pipeline tab** to identify jobs that need follow-up
- **Monitor the Payouts tab** to stay aware of pending referral rewards

### Pipeline Management

- Follow up on estimates in **Estimate Sent** status within 3--5 days
- Confirm pre-wire dates are scheduled promptly after signing
- Ensure installers update job status after each milestone (pre-wire complete, install complete)

### Team Coordination

- Review installer workloads before assigning new jobs
- Keep installer contact information current — notify Nex-Gen admin of any changes
- When an installer leaves your company, request deactivation immediately to disable their PIN

### Referral Promotion

- Share referral program details with every customer at handoff
- Remind customers that sharing their code earns them real rewards
- Point customers to the **Refer & Earn** screen in the app (Settings section)

---

## 11. Quick Reference

| Action | Where |
|--------|-------|
| View business overview | Dealer Dashboard > Overview tab |
| See all sales jobs | Dealer Dashboard > Pipeline tab |
| Check installer roster | Dealer Dashboard > Team tab |
| View referral payouts | Dealer Dashboard > Payouts tab |
| View job details | Tap any job in the Pipeline list |
| See recent activity | Overview tab > Recent Activity feed |
| Check pending payouts count | Overview tab > Pending Payouts stat card |
| Access Refer & Earn (customer-facing) | Settings > Refer & Earn |

---

## 12. Frequently Asked Questions

### Why does the dashboard show "No active dealer session"?

You must enter the Dealer Dashboard through a valid sales or installer session. If your session has expired (sessions timeout after 30 minutes of inactivity), re-enter your PIN to start a new session.

### Can I edit a sales job from the dashboard?

The dashboard is a read-only view of your pipeline. To update a job's status or details, use the Sales Mode workflow where jobs are created and advanced through each stage.

### Why was a referral reward issued as Nex-Gen Credit instead of a gift card?

The referrer hit the **$599 annual Visa gift card cap**. When this happens, the system automatically switches to Nex-Gen Credit at the higher credit rate. This benefits the referrer — credit rewards are worth more than gift card rewards at every tier.

### How do I get a new installer added?

Contact the Nex-Gen admin team with the installer's name, email, and phone number. They will create the installer under your dealer code and provide the new 4-digit PIN.

### Can I view another dealer's dashboard?

No. Each dealer session is scoped to your dealer code. Only Nex-Gen administrators can view dashboards across dealers using the Admin Portal.

---

## 13. Support

For questions about your Dealer Dashboard or sales pipeline:

- **General support:** support@nexgenled.com
- **Payout questions:** payouts@nexgenled.com
- **Technical issues or app bugs:** Contact the Nex-Gen admin team directly
- **Installer management requests:** Contact your Nex-Gen administrator

For the full guide on completing customer installations, see the **[Dealer & Installer Setup Guide](Dealer_Installer_Setup_Guide.md)**.

For administrator operations (creating dealers, managing installers, viewing all installations), see the **[Admin Operations Guide](Admin_Operations_Guide.md)**.

---

*Nex-Gen Lumina v2.1 — Dealer Dashboard Guide — April 2026*
