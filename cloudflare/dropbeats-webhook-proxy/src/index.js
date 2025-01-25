// Supabase details
const SUPABASE_URL = 'https://trtxfdsssreqhuajpvqk.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRydHhmZHNzc3JlcWh1YWpwdnFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYzNTY5MTIsImV4cCI6MjA1MTkzMjkxMn0.CYDp3xGrlILUsjP2yzT3Y1cFGyACP57R3awfQvs35A4'

// Expected Gumroad product details
const DROPBEATS_PRODUCT_ID = '1MCDeB0zEW1je0kaXIy40Q=='
const DROPBEATS_SELLER_ID = 'A-m092IeKpvCZ4yFpcaoeA=='

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': '*'
}

export default {
  async fetch(request, env, ctx) {
    // Log everything immediately
    console.log('=== NEW REQUEST RECEIVED ===')
    console.log('Time:', new Date().toISOString())
    console.log('Method:', request.method)
    console.log('URL:', request.url)
    console.log('Headers:', Object.fromEntries(request.headers.entries()))

    try {
      // Handle CORS preflight
      if (request.method === 'OPTIONS') {
        console.log('Handling CORS preflight')
        return new Response(null, {
          status: 204,
          headers: corsHeaders
        })
      }

      // If it's a GET request, return instructions
      if (request.method === 'GET') {
        console.log('Handling GET request - this is normal for Gumroad ping test')
        return new Response(JSON.stringify({
          status: 'ready',
          message: 'DropBeats webhook endpoint is ready. If you see this after clicking "Send ping", Gumroad will send a POST request next with test data.',
          version: '2.0.0',
          last_updated: '2025-01-18',
          note: 'This GET response is expected. Check logs for the actual POST webhook data.'
        }), {
          status: 200,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        })
      }

      // For POST requests, log extensively
      console.log('=== POST REQUEST RECEIVED ===')
      console.log('Headers:', Object.fromEntries(request.headers.entries()))
      console.log('Time:', new Date().toISOString())
      
      // Get raw body immediately and log it
      const rawBody = await request.text()
      console.log('Raw body received:', rawBody)
      console.log('Raw body length:', rawBody.length)

      // Try parsing as form data
      const formData = new URLSearchParams(rawBody)
      const formDataObj = Object.fromEntries(formData.entries())
      console.log('Parsed as form data:', formDataObj)

      // Try parsing as JSON
      let jsonData = {}
      try {
        jsonData = JSON.parse(rawBody)
        console.log('Parsed as JSON:', jsonData)
      } catch (e) {
        console.log('Not valid JSON:', e.message)
      }

      // Use form data by default
      const data = formDataObj

      // Log all available data
      console.log('=== PROCESSED DATA ===')
      console.log('Content-Type:', request.headers.get('content-type'))
      console.log('Available fields:', Object.keys(data))
      console.log('Data values:', data)

      // Validate it's for DropBeats
      if (data.product_id !== DROPBEATS_PRODUCT_ID || data.seller_id !== DROPBEATS_SELLER_ID) {
        console.log('Product validation failed:', {
          received_product_id: data.product_id,
          received_seller_id: data.seller_id,
          expected_product_id: DROPBEATS_PRODUCT_ID,
          expected_seller_id: DROPBEATS_SELLER_ID
        })
        return new Response(JSON.stringify({
          status: 'ignored',
          reason: 'not for DropBeats',
          received_product: {
            product_id: data.product_id || 'not set',
            seller_id: data.seller_id || 'not set'
          }
        }))
      }

      // Forward to Supabase database directly
      console.log('Preparing license data...')
      const licenseData = {
        email: data.email || data.purchase_email,
        license_key: data.license_key,
        created_at: new Date().toISOString()
      }
      console.log('License data:', licenseData)

      console.log('Sending to Supabase...')
      const response = await fetch(`${SUPABASE_URL}/rest/v1/licenses`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'apikey': `${SUPABASE_ANON_KEY}`,
          'Prefer': 'return=representation'
        },
        body: JSON.stringify(licenseData)
      })

      // Get and log Supabase's response in detail
      const result = await response.text()
      console.log('Supabase response status:', response.status)
      console.log('Supabase response headers:', Object.fromEntries(response.headers.entries()))
      console.log('Supabase response body:', result)

      // Return success to Gumroad with more details
      return new Response(JSON.stringify({
        status: 'success',
        message: 'License created',
        email: data.email || data.purchase_email,
        license_key: data.license_key,
        price: parseFloat(data.price || '0'),
        test: data.test === 'true'
      }), {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      })

    } catch (err) {
      console.error('=== ERROR PROCESSING REQUEST ===')
      console.error('Error:', err)
      console.error('Stack:', err.stack)
      return new Response(
        JSON.stringify({ 
          status: 'error',
          reason: err.message,
          stack: err.stack
        }),
        {
          status: 200,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      )
    }
  }
} 