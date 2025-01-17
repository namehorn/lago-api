# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::AddOnService, type: :service do
  subject(:invoice_service) do
    described_class.new(subscription: subscription, applied_add_on: applied_add_on, date: date)
  end
  let(:date) { Time.zone.now.to_date }
  let(:applied_add_on) { create(:applied_add_on) }

  describe 'create' do
    let(:plan) { create(:plan, interval: 'monthly') }
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        subscription_date: (Time.zone.now - 2.years).to_date,
        started_at: Time.zone.now - 2.years,
      )
    end

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }

    before do
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.to_date).to eq(date)
        expect(result.invoice.from_date).to eq(date)
        expect(result.invoice.subscription).to eq(subscription)
        expect(result.invoice.issuing_date).to eq(date)
        expect(result.invoice.invoice_type).to eq('add_on')
        expect(result.invoice.status).to eq('pending')

        expect(result.invoice.amount_cents).to eq(200)
        expect(result.invoice.amount_currency).to eq('EUR')
        expect(result.invoice.vat_amount_cents).to eq(40)
        expect(result.invoice.vat_amount_currency).to eq('EUR')
        expect(result.invoice.total_amount_cents).to eq(240)
        expect(result.invoice.total_amount_currency).to eq('EUR')
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    context 'when organization does not have a webhook url' do
      before { subscription.organization.update!(webhook_url: nil) }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when customer payment_provider is stripe' do
      before { subscription.customer.update!(payment_provider: 'stripe') }

      it 'enqueu a job to create a payment' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(Invoices::Payments::StripeCreateJob)
      end
    end
  end
end
