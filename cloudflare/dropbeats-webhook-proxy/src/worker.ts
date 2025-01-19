import { createClient } from '@supabase/supabase-js'

interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Log everything immediately
    console.log('New request received')
    console.log('Method:', request.method)
    console.log('Headers:', Object.fromEntries(request.headers.entries()))
    
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders })
    }

    // Handle GET requests with a friendly message
    if (request.method === 'GET') {
      return new Response(
        JSON.stringify({
          message: 'DropBeats webhook endpoint is ready for Gumroad sale notifications.',
          version: '1.0.0',
          lastUpdated: new Date().toISOString().split('T')[0],
          usage: 'Send POST requests with application/x-www-form-urlencoded content type'
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

    try {
      // Only proceed with FormData parsing for POST requests
      if (request.method !== 'POST') {
        return new Response(
          JSON.stringify({ error: 'Method not allowed. Only POST requests are accepted for webhooks.' }),
          { 
            status: 405, 
            headers: { 
              ...corsHeaders,
              'Content-Type': 'application/json'
            }
          }
        )
      }

      // Get form data
      const formData = await request.formData()
      const payload: Record<string, any> = {}
      
      // Convert FormData to object and log each field
      for (const [key, value] of formData.entries()) {
        console.log(`Form field ${key}:`, value)
        payload[key] = value
      }
      
      console.log('Parsed payload:', payload)

      // Create Supabase client
      console.log('Creating Supabase client...')
      const supabaseAdmin = createClient(
        env.SUPABASE_URL,
        env.SUPABASE_SERVICE_ROLE_KEY
      )

      // Store the webhook data
      console.log('Storing webhook data...')
      const { data, error } = await supabaseAdmin
        .from('licenses')
        .upsert({
          email: payload.email,
          full_name: payload['Your Name'] || payload.custom_fields?.['Your Name'] || null,
          phone_number: payload['Mobile Number'] || payload.custom_fields?.['Mobile Number'] || null,
          country: payload.country || payload.ip_country || null,
          license_key: payload.license_key,
          sale_id: payload.sale_id,
          created_at: payload.sale_timestamp || new Date().toISOString(),
          device_id: null,
          is_active: true,
          is_beta: true,
          has_completed_onboarding: false
        }, {
          onConflict: 'email',
          ignoreDuplicates: false
        })

      if (error) {
        console.error('Database error:', error)
        return new Response(
          JSON.stringify({ error: error.message }),
          { 
            status: 500, 
            headers: { 
              ...corsHeaders,
              'Content-Type': 'application/json'
            }
          }
        )
      }

      console.log('Success! Database response:', data)
      return new Response(
        JSON.stringify({ status: 'success', data }),
        { 
          status: 200, 
          headers: { 
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      )

    } catch (err: any) {
      console.error('Error:', err)
      return new Response(
        JSON.stringify({ error: err.message || 'Unknown error occurred' }),
        { 
          status: 500, 
          headers: { 
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      )
    }
  }
} 