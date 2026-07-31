FactoryBot.define do
  factory :identity_document, class: "Identity::Document" do
    association :identity
    document_type { :government_id }

    after(:build) do |doc|
      doc.files.attach(
        io: StringIO.new("fake image data"),
        filename: "id_front.jpg",
        content_type: "image/jpeg"
      )
    end

    trait :transcript do
      document_type { :transcript }

      after(:build) do |doc|
        doc.files.attach(
          io: StringIO.new("fake transcript"),
          filename: "transcript.pdf",
          content_type: "image/jpeg"
        )
      end
    end
  end

  factory :document_verification, class: "Verification::DocumentVerification" do
    association :identity
    association :identity_document
    status { :pending }
  end

  factory :aadhaar_verification, class: "Verification::AadhaarVerification" do
    association :identity
    status { :draft }
    aadhaar_hc_transaction_id { "HC!#{SecureRandom.uuid}" }
  end

  factory :vouch_verification, class: "Verification::VouchVerification" do
    association :identity
    status { :approved }

    after(:build) do |vouch|
      vouch.evidence.attach(
        io: StringIO.new("vouch evidence"),
        filename: "evidence.pdf",
        content_type: "application/pdf"
      )
    end
  end
end

