# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedCoupons::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization: organization) }
  let(:customer_id) { customer.id }

  let(:coupon) { create(:coupon, status: 'active', organization: organization) }
  let(:coupon_id) { coupon.id }

  let(:amount_cents) { nil }
  let(:amount_currency) { nil }

  before do
    create(:active_subscription, customer_id: customer_id) if customer
  end

  describe 'create' do
    let(:create_args) do
      {
        coupon_id: coupon_id,
        customer_id: customer_id,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
        organization_id: organization.id,
      }
    end

    let(:create_result) { create_service.create(**create_args) }

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'applied the coupon to the customer' do
      expect { create_result }.to change(AppliedCoupon, :count).by(1)

      expect(create_result.applied_coupon.customer).to eq(customer)
      expect(create_result.applied_coupon.coupon).to eq(coupon)
      expect(create_result.applied_coupon.amount_cents).to eq(coupon.amount_cents)
      expect(create_result.applied_coupon.amount_currency).to eq(coupon.amount_currency)
    end

    it 'calls SegmentTrackJob' do
      applied_coupon = create_result.applied_coupon

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'applied_coupon_created',
        properties: {
          customer_id: applied_coupon.customer.id,
          coupon_code: applied_coupon.coupon.code,
          coupon_name: applied_coupon.coupon.name,
          organization_id: applied_coupon.coupon.organization_id
        }
      )
    end

    context 'with overridden amount' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_coupon.amount_cents).to eq(123) }
      it { expect(create_result.applied_coupon.amount_currency).to eq('EUR') }

      context 'when currency does not match' do
        let(:amount_currency) { 'NOK' }

        it { expect(create_result).not_to be_success }
        it { expect(create_result.error).to eq('currencies_does_not_match') }
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }
      let(:customer_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('unable_to_find_customer') }
    end

    context 'when coupon is not found' do
      let(:coupon_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('coupon_does_not_exist') }
    end

    context 'when coupon is inactive' do
      before { coupon.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('coupon_does_not_exist') }
    end

    context 'when customer does not have a subscription' do
      before { customer.active_subscription.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('no_active_subscription') }
    end

    context 'when coupon is already applied to the customer' do
      before { create(:applied_coupon, customer: customer, coupon: coupon) }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('coupon_already_applied') }
    end

    context 'when an other coupon is already applied to the customer' do
      let(:other_coupon) { create(:coupon, status: 'active', organization: organization) }

      before { create(:applied_coupon, customer: customer, coupon: other_coupon) }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('coupon_already_applied') }
    end

    context 'when currency of coupon does not match customer currency' do
      let(:coupon) { create(:coupon, status: 'active', organization: organization, amount_currency: 'NOK') }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('currencies_does_not_match') }
    end
  end

  describe 'create_from_api' do
    let(:coupon_code) { coupon&.code }
    let(:external_customer_id) { customer&.customer_id }

    let(:create_args) do
      {
        coupon_code: coupon_code,
        customer_id: external_customer_id,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      }
    end

    let(:create_result) do
      create_service.create_from_api(
        organization: organization,
        args: create_args,
      )
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'applies the coupon to the customer' do
      expect { create_result }.to change(AppliedCoupon, :count).by(1)

      expect(create_result.applied_coupon.customer).to eq(customer)
      expect(create_result.applied_coupon.coupon).to eq(coupon)
      expect(create_result.applied_coupon.amount_cents).to eq(coupon.amount_cents)
      expect(create_result.applied_coupon.amount_currency).to eq(coupon.amount_currency)
    end

    it 'calls SegmentTrackJob' do
      applied_coupon = create_result.applied_coupon

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'applied_coupon_created',
        properties: {
          customer_id: applied_coupon.customer.id,
          coupon_code: applied_coupon.coupon.code,
          coupon_name: applied_coupon.coupon.name,
          organization_id: applied_coupon.coupon.organization_id
        }
      )
    end

    context 'with overridden amount' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_coupon.amount_cents).to eq(123) }
      it { expect(create_result.applied_coupon.amount_currency).to eq('EUR') }

      context 'when currency does not match' do
        let(:amount_currency) { 'NOK' }

        it { expect(create_result).not_to be_success }
        it { expect(create_result.error).to eq('currencies_does_not_match') }
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }
      let(:customer_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('unable_to_find_customer') }
    end

    context 'when coupon is not found' do
      let(:coupon_code) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('coupon_does_not_exist') }
    end

    context 'when coupon is inactive' do
      before { coupon.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('coupon_does_not_exist') }
    end

    context 'when customer does not have a subscription' do
      before { customer.active_subscription.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('no_active_subscription') }
    end

    context 'when coupon is already applied to the customer' do
      before { create(:applied_coupon, customer: customer, coupon: coupon) }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('coupon_already_applied') }
    end

    context 'when currency of coupon does not match customer currency' do
      let(:coupon) { create(:coupon, status: 'active', organization: organization, amount_currency: 'NOK') }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('currencies_does_not_match') }
    end
  end
end
