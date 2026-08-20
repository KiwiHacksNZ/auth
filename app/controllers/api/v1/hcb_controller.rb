module API
  module V1
    class HCBController < ApplicationController
      def show
        render json: { pending: Verification.where(status: "pending").count }
      end
    end
  end
end
