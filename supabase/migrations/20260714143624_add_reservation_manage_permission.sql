-- Allow administrators to control access to the reservation workspace and
-- reservation lifecycle actions independently from creating new bookings.
ALTER TABLE public.account_permissions
  DROP CONSTRAINT IF EXISTS account_permissions_permission_key_check;

ALTER TABLE public.account_permissions
  ADD CONSTRAINT account_permissions_permission_key_check
  CHECK (permission_key IN (
    'booking.create',
    'reservation.manage',
    'payment.create',
    'wallet.deposit',
    'users.create'
  ));
