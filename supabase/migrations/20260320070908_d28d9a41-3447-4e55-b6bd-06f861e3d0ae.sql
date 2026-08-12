CREATE TABLE public.test_centers (
  site_id integer PRIMARY KEY,
  name text NOT NULL,
  city text,
  address text,
  country_code text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.test_centers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read test centers"
  ON public.test_centers FOR SELECT
  TO anon, authenticated
  USING (true);

INSERT INTO public.test_centers (site_id, name, city, address, country_code) VALUES
  (1, 'Bangladesh German TTC', 'Dhaka', 'Mirpur -2, Dhaka 1216, Bangladesh', '+880')
ON CONFLICT (site_id) DO NOTHING;