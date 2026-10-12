SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('partner_commission_settings','partner_commission_partners','partner_commission_assignments','partner_commission_payment_events','partner_commission_ledger','partner_commission_payouts','partner_commission_payout_items','partner_commission_audit') ORDER BY TABLE_NAME;
SELECT id,default_rate,default_mode,referral_window_days FROM partner_commission_settings WHERE id=1;
SELECT COUNT(*) AS partners FROM partner_commission_partners;
SELECT COUNT(*) AS active_assignments FROM partner_commission_assignments WHERE status='active';
SELECT COUNT(*) AS commissions FROM partner_commission_ledger;