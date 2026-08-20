FactoryBot.define do
  factory :address do
    association :identity
    first_name { "Kiki" }
    last_name { "Hackworth" }
    line_1 { "12 Queen Street" }
    line_2 { "Level 3" }
    city { "Auckland" }
    state { "Auckland" }
    postal_code { "1010" }
    country { "NZ" }
    phone_number { "+64211234567" }
  end
end
