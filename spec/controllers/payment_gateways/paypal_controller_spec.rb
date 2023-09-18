# frozen_string_literal: true

require 'spec_helper'

module PaymentGateways
  describe PaypalController, type: :controller do
    context '#cancel' do
      it 'redirects back to checkout' do
        expect(get(:cancel)).to redirect_to checkout_path
      end
    end

    context '#confirm' do
      let(:previous_order) { controller.current_order(true) }
      let(:payment_method) { create(:payment_method) }

      before do
        allow(previous_order).to receive(:complete?).and_return(true)
        allow(previous_order).to receive(:checkout_allowed?).and_return(true)
      end

      it 'resets the order' do
        post :confirm, params: { payment_method_id: payment_method.id }
        expect(controller.current_order).not_to eq(previous_order)
      end

      it 'sets the access token of the session' do
        post :confirm, params: { payment_method_id: payment_method.id }
        expect(session[:access_token]).to eq(controller.current_order.token)
      end

      context "if the stock ran out whilst the payment was being placed" do
        before do
          allow(controller.current_order).to receive(:insufficient_stock_lines).and_return(true)
        end

        it "redirects to the cart with out of stock error" do
          expect(post(:confirm, params: { payment_method_id: payment_method.id })).
            to redirect_to cart_path

          order = controller.current_order.reload

          # Order is in "cart" state and did not complete processing of the payment
          expect(order.state).to eq "cart"
          expect(order.payments.count).to eq 0
        end
      end

      context "when order completion fails" do
        before do
          allow(previous_order).to receive(:complete?).and_return(false)
        end

        it "redirects to checkout state path" do
          expect(post(:confirm, params: { payment_method_id: payment_method.id })).
            to redirect_to checkout_step_path(step: :payment)

          expect(flash[:error]).to eq(
            'Payment could not be processed, please check the details you entered'
          )
        end
      end
    end

    describe "#express" do
      let(:order) { create(:order_with_totals_and_distribution) }
      let(:response) { true }
      let(:provider_success_url) { "https://test.com/success" }
      let(:response_mock) { double(:response, success?: response, errors: [] ) }
      let(:provider_mock) {
        double(:provider, build_set_express_checkout: true,
                          set_express_checkout: response_mock,
                          express_checkout_url: provider_success_url)
      }

      before do
        allow(controller).to receive(:current_order) { order }
        allow(controller).to receive(:provider) { provider_mock }
        allow(controller).to receive(:express_checkout_request_details) { {} }
      end

      context "when processing is successful" do
        it "redirects to a success URL generated by the payment provider" do
          expect(post(:express)).to redirect_to provider_success_url
        end
      end

      context "when processing fails" do
        let(:response) { false }

        it "redirects to checkout_step_path with a flash error" do
          expect(post(:express)).to redirect_to checkout_step_path(:payment)
          expect(flash[:error]).to eq "PayPal failed. "
        end
      end

      context "when a SocketError is encountered during processing" do
        before do
          allow(response_mock).to receive(:success?).and_raise(SocketError)
        end

        it "redirects to checkout_step_path with a flash error" do
          expect(post(:express)).to redirect_to checkout_step_path(:payment)
          expect(flash[:error]).to eq "Could not connect to PayPal."
        end
      end
    end

    describe '#expire_current_order' do
      it 'empties the order_id of the session' do
        expect(session).to receive(:[]=).with(:order_id, nil)
        controller.send(:expire_current_order)
      end

      it 'resets the @current_order ivar' do
        controller.send(:expire_current_order)
        expect(controller.instance_variable_get(:@current_order)).to be_nil
      end
    end
  end
end
