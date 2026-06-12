/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      blocks: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
          id: string
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
          id?: string
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocks_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocks_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cadence_outcome_events: {
        Row: {
          account_id: string
          consumed_by_frisfocus: boolean
          created_at: string
          event_type: string
          id: string
          metrics: Json
          occurred_at: string
          routine_id: string | null
          source_app: string
          verified: boolean
        }
        Insert: {
          account_id: string
          consumed_by_frisfocus?: boolean
          created_at?: string
          event_type: string
          id?: string
          metrics?: Json
          occurred_at?: string
          routine_id?: string | null
          source_app?: string
          verified?: boolean
        }
        Update: {
          account_id?: string
          consumed_by_frisfocus?: boolean
          created_at?: string
          event_type?: string
          id?: string
          metrics?: Json
          occurred_at?: string
          routine_id?: string | null
          source_app?: string
          verified?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "cadence_outcome_events_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cadence_outcome_events_routine_id_fkey"
            columns: ["routine_id"]
            isOneToOne: false
            referencedRelation: "cadence_routines"
            referencedColumns: ["id"]
          },
        ]
      }
      cadence_routines: {
        Row: {
          account_id: string
          created_at: string
          est_minutes: number
          id: string
          kind: string | null
          name: string
          step_count: number
          updated_at: string
        }
        Insert: {
          account_id: string
          created_at?: string
          est_minutes?: number
          id?: string
          kind?: string | null
          name: string
          step_count?: number
          updated_at?: string
        }
        Update: {
          account_id?: string
          created_at?: string
          est_minutes?: number
          id?: string
          kind?: string | null
          name?: string
          step_count?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cadence_routines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cheers: {
        Row: {
          created_at: string
          dismissed_at: string | null
          id: string
          message: string
          reaction: string | null
          reaction_at: string | null
          read_at: string | null
          recipient_id: string
          sender_id: string
        }
        Insert: {
          created_at?: string
          dismissed_at?: string | null
          id?: string
          message: string
          reaction?: string | null
          reaction_at?: string | null
          read_at?: string | null
          recipient_id: string
          sender_id: string
        }
        Update: {
          created_at?: string
          dismissed_at?: string | null
          id?: string
          message?: string
          reaction?: string | null
          reaction_at?: string | null
          read_at?: string | null
          recipient_id?: string
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cheers_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cheers_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_contributions: {
        Row: {
          amount: number
          circle_id: string
          created_at: string
          id: string
          note: string | null
          user_id: string
        }
        Insert: {
          amount: number
          circle_id: string
          created_at?: string
          id?: string
          note?: string | null
          user_id: string
        }
        Update: {
          amount?: number
          circle_id?: string
          created_at?: string
          id?: string
          note?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_contributions_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_contributions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_invitations: {
        Row: {
          circle_id: string
          created_at: string
          id: string
          invitee_id: string
          inviter_id: string
          responded_at: string | null
          status: string
        }
        Insert: {
          circle_id: string
          created_at?: string
          id?: string
          invitee_id: string
          inviter_id: string
          responded_at?: string | null
          status?: string
        }
        Update: {
          circle_id?: string
          created_at?: string
          id?: string
          invitee_id?: string
          inviter_id?: string
          responded_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_invitations_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_invitations_invitee_id_fkey"
            columns: ["invitee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_invitations_inviter_id_fkey"
            columns: ["inviter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_join_requests: {
        Row: {
          circle_id: string
          created_at: string
          id: string
          requester_id: string
          responded_at: string | null
          status: string
        }
        Insert: {
          circle_id: string
          created_at?: string
          id?: string
          requester_id: string
          responded_at?: string | null
          status?: string
        }
        Update: {
          circle_id?: string
          created_at?: string
          id?: string
          requester_id?: string
          responded_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_join_requests_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_join_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_members: {
        Row: {
          circle_id: string
          id: string
          joined_at: string
          role: string
          user_id: string
        }
        Insert: {
          circle_id: string
          id?: string
          joined_at?: string
          role?: string
          user_id: string
        }
        Update: {
          circle_id?: string
          id?: string
          joined_at?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_members_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_task_completions: {
        Row: {
          circle_id: string
          completed_on: string
          created_at: string
          id: string
          task_id: string
          user_id: string
        }
        Insert: {
          circle_id: string
          completed_on?: string
          created_at?: string
          id?: string
          task_id: string
          user_id: string
        }
        Update: {
          circle_id?: string
          completed_on?: string
          created_at?: string
          id?: string
          task_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_task_completions_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_task_completions_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "circle_tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_task_completions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_tasks: {
        Row: {
          circle_id: string
          created_at: string
          id: string
          point_value: number | null
          position: number
          title: string
        }
        Insert: {
          circle_id: string
          created_at?: string
          id?: string
          point_value?: number | null
          position?: number
          title: string
        }
        Update: {
          circle_id?: string
          created_at?: string
          id?: string
          point_value?: number | null
          position?: number
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_tasks_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
        ]
      }
      circles: {
        Row: {
          collective_target: number | null
          collective_unit: string | null
          created_at: string
          description: string | null
          end_date: string | null
          header_url: string | null
          id: string
          join_rule: string
          name: string
          owner_id: string
          timeframe_kind: string
          type: string
          visibility: string
        }
        Insert: {
          collective_target?: number | null
          collective_unit?: string | null
          created_at?: string
          description?: string | null
          end_date?: string | null
          header_url?: string | null
          id?: string
          join_rule?: string
          name: string
          owner_id: string
          timeframe_kind?: string
          type?: string
          visibility?: string
        }
        Update: {
          collective_target?: number | null
          collective_unit?: string | null
          created_at?: string
          description?: string | null
          end_date?: string | null
          header_url?: string | null
          id?: string
          join_rule?: string
          name?: string
          owner_id?: string
          timeframe_kind?: string
          type?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "circles_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contact_keys: {
        Row: {
          phone: string | null
          phone_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          phone?: string | null
          phone_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Update: {
          phone?: string | null
          phone_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      device_tokens: {
        Row: {
          created_at: string
          platform: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          platform?: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          platform?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      direct_messages: {
        Row: {
          body: string | null
          created_at: string
          id: string
          kind: string
          media_duration: number | null
          media_kind: string | null
          media_path: string | null
          read_at: string | null
          recipient_id: string
          sender_id: string
          watched_at: string | null
        }
        Insert: {
          body?: string | null
          created_at?: string
          id?: string
          kind?: string
          media_duration?: number | null
          media_kind?: string | null
          media_path?: string | null
          read_at?: string | null
          recipient_id: string
          sender_id: string
          watched_at?: string | null
        }
        Update: {
          body?: string | null
          created_at?: string
          id?: string
          kind?: string
          media_duration?: number | null
          media_kind?: string | null
          media_path?: string | null
          read_at?: string | null
          recipient_id?: string
          sender_id?: string
          watched_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "direct_messages_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "direct_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      esengo_entitlements: {
        Row: {
          account_id: string
          created_at: string
          id: string
          product: string
          renews_at: string | null
          source: string | null
          status: string
          updated_at: string
        }
        Insert: {
          account_id: string
          created_at?: string
          id?: string
          product: string
          renews_at?: string | null
          source?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          account_id?: string
          created_at?: string
          id?: string
          product?: string
          renews_at?: string | null
          source?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "esengo_entitlements_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      focus_blocks: {
        Row: {
          ended_at: string | null
          host_id: string
          id: string
          label: string | null
          planned_minutes: number
          started_at: string
        }
        Insert: {
          ended_at?: string | null
          host_id: string
          id?: string
          label?: string | null
          planned_minutes?: number
          started_at?: string
        }
        Update: {
          ended_at?: string | null
          host_id?: string
          id?: string
          label?: string | null
          planned_minutes?: number
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "focus_blocks_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      focus_participants: {
        Row: {
          block_id: string
          id: string
          leaf_tier: string
          state: string
          updated_at: string
          user_id: string
        }
        Insert: {
          block_id: string
          id?: string
          leaf_tier?: string
          state?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          block_id?: string
          id?: string
          leaf_tier?: string
          state?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "focus_participants_block_id_fkey"
            columns: ["block_id"]
            isOneToOne: false
            referencedRelation: "focus_blocks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "focus_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      friend_requests: {
        Row: {
          addressee_id: string
          created_at: string
          id: string
          requester_id: string
          responded_at: string | null
          status: string
        }
        Insert: {
          addressee_id: string
          created_at?: string
          id?: string
          requester_id: string
          responded_at?: string | null
          status?: string
        }
        Update: {
          addressee_id?: string
          created_at?: string
          id?: string
          requester_id?: string
          responded_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "friend_requests_addressee_id_fkey"
            columns: ["addressee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "friend_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      friendships: {
        Row: {
          created_at: string
          id: string
          user_a: string
          user_b: string
        }
        Insert: {
          created_at?: string
          id?: string
          user_a: string
          user_b: string
        }
        Update: {
          created_at?: string
          id?: string
          user_a?: string
          user_b?: string
        }
        Relationships: [
          {
            foreignKeyName: "friendships_user_a_fkey"
            columns: ["user_a"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "friendships_user_b_fkey"
            columns: ["user_b"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      golden_hour_picks: {
        Row: {
          circle_id: string
          created_at: string
          day: string
          fire_minute: number
          id: string
          picker_id: string
        }
        Insert: {
          circle_id: string
          created_at?: string
          day: string
          fire_minute: number
          id?: string
          picker_id: string
        }
        Update: {
          circle_id?: string
          created_at?: string
          day?: string
          fire_minute?: number
          id?: string
          picker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "golden_hour_picks_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
        ]
      }
      golden_hour_posts: {
        Row: {
          circle_id: string
          day: string
          fired_at: string
          id: string
          media_duration: number | null
          media_kind: string
          media_path: string | null
          posted_at: string
          seconds_to_spare: number | null
          user_id: string
        }
        Insert: {
          circle_id: string
          day: string
          fired_at: string
          id?: string
          media_duration?: number | null
          media_kind?: string
          media_path?: string | null
          posted_at?: string
          seconds_to_spare?: number | null
          user_id: string
        }
        Update: {
          circle_id?: string
          day?: string
          fired_at?: string
          id?: string
          media_duration?: number | null
          media_kind?: string
          media_path?: string | null
          posted_at?: string
          seconds_to_spare?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "golden_hour_posts_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
        ]
      }
      golden_hour_settings: {
        Row: {
          circle_id: string
          enabled: boolean
          fire_minute: number
          mode: string
          time_zone: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          circle_id: string
          enabled?: boolean
          fire_minute?: number
          mode?: string
          time_zone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          circle_id?: string
          enabled?: boolean
          fire_minute?: number
          mode?: string
          time_zone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "golden_hour_settings_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: true
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
        ]
      }
      note_folders: {
        Row: {
          color_key: string
          id: string
          name: string
          updated_at: string
          user_id: string
        }
        Insert: {
          color_key?: string
          id: string
          name: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          color_key?: string
          id?: string
          name?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      notes: {
        Row: {
          body: string | null
          created_at: string
          folder_id: string | null
          id: string
          is_pinned: boolean
          label: string | null
          photos: Json
          tags: string[]
          updated_at: string
          user_id: string
          voice_memos: Json
        }
        Insert: {
          body?: string | null
          created_at?: string
          folder_id?: string | null
          id: string
          is_pinned?: boolean
          label?: string | null
          photos?: Json
          tags?: string[]
          updated_at?: string
          user_id?: string
          voice_memos?: Json
        }
        Update: {
          body?: string | null
          created_at?: string
          folder_id?: string | null
          id?: string
          is_pinned?: boolean
          label?: string | null
          photos?: Json
          tags?: string[]
          updated_at?: string
          user_id?: string
          voice_memos?: Json
        }
        Relationships: []
      }
      pact_completions: {
        Row: {
          completed_on: string
          created_at: string
          id: string
          pact_id: string
          task_id: string
          user_id: string
        }
        Insert: {
          completed_on?: string
          created_at?: string
          id?: string
          pact_id: string
          task_id: string
          user_id: string
        }
        Update: {
          completed_on?: string
          created_at?: string
          id?: string
          pact_id?: string
          task_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pact_completions_pact_id_fkey"
            columns: ["pact_id"]
            isOneToOne: false
            referencedRelation: "pacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pact_completions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      pact_tasks: {
        Row: {
          id: string
          pact_id: string
          position: number
          title: string
        }
        Insert: {
          id?: string
          pact_id: string
          position?: number
          title: string
        }
        Update: {
          id?: string
          pact_id?: string
          position?: number
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "pact_tasks_pact_id_fkey"
            columns: ["pact_id"]
            isOneToOne: false
            referencedRelation: "pacts"
            referencedColumns: ["id"]
          },
        ]
      }
      pacts: {
        Row: {
          created_at: string
          duration_days: number
          end_date: string | null
          id: string
          partner_id: string
          proposer_id: string
          responded_at: string | null
          start_date: string | null
          status: string
          title: string | null
        }
        Insert: {
          created_at?: string
          duration_days?: number
          end_date?: string | null
          id?: string
          partner_id: string
          proposer_id: string
          responded_at?: string | null
          start_date?: string | null
          status?: string
          title?: string | null
        }
        Update: {
          created_at?: string
          duration_days?: number
          end_date?: string | null
          id?: string
          partner_id?: string
          proposer_id?: string
          responded_at?: string | null
          start_date?: string | null
          status?: string
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pacts_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pacts_proposer_id_fkey"
            columns: ["proposer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          area_key: string | null
          area_name: string | null
          avatar_url: string | null
          bio: string | null
          created_at: string | null
          email: string | null
          header_url: string | null
          id: string
          is_test: boolean
          name: string | null
          season_card: string | null
          updated_at: string | null
          username: string | null
        }
        Insert: {
          area_key?: string | null
          area_name?: string | null
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          email?: string | null
          header_url?: string | null
          id: string
          is_test?: boolean
          name?: string | null
          season_card?: string | null
          updated_at?: string | null
          username?: string | null
        }
        Update: {
          area_key?: string | null
          area_name?: string | null
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          email?: string | null
          header_url?: string | null
          id?: string
          is_test?: boolean
          name?: string | null
          season_card?: string | null
          updated_at?: string | null
          username?: string | null
        }
        Relationships: []
      }
      reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          message_id: string | null
          reason: string
          reported_user_id: string | null
          reporter_id: string
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          message_id?: string | null
          reason: string
          reported_user_id?: string | null
          reporter_id: string
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          message_id?: string | null
          reason?: string
          reported_user_id?: string | null
          reporter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "direct_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reported_user_id_fkey"
            columns: ["reported_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      season_sync: {
        Row: {
          payload: string
          slice_key: string
          updated_at: string
          user_id: string
        }
        Insert: {
          payload: string
          slice_key: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          payload?: string
          slice_key?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      story_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          post_id: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          post_id: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "story_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "story_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "story_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      story_likes: {
        Row: {
          created_at: string
          id: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "story_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "story_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "story_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      story_posts: {
        Row: {
          attached_task_id: string | null
          author_id: string
          caption: string | null
          circle_id: string | null
          created_at: string
          id: string
          media_duration: number | null
          media_kind: string | null
          media_path: string | null
          media_url: string | null
        }
        Insert: {
          attached_task_id?: string | null
          author_id: string
          caption?: string | null
          circle_id?: string | null
          created_at?: string
          id?: string
          media_duration?: number | null
          media_kind?: string | null
          media_path?: string | null
          media_url?: string | null
        }
        Update: {
          attached_task_id?: string | null
          author_id?: string
          caption?: string | null
          circle_id?: string | null
          created_at?: string
          id?: string
          media_duration?: number | null
          media_kind?: string | null
          media_path?: string | null
          media_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "story_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "story_posts_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
        ]
      }
      story_views: {
        Row: {
          created_at: string
          id: string
          post_id: string
          viewer_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          post_id: string
          viewer_id: string
        }
        Update: {
          created_at?: string
          id?: string
          post_id?: string
          viewer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "story_views_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "story_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "story_views_viewer_id_fkey"
            columns: ["viewer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      test_engine_state: {
        Row: {
          data: Json
          id: string
          last_run_at: string | null
        }
        Insert: {
          data?: Json
          id: string
          last_run_at?: string | null
        }
        Update: {
          data?: Json
          id?: string
          last_run_at?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      are_friends: { Args: { other_id: string }; Returns: boolean }
      can_see_story: { Args: { p_post_id: string }; Returns: boolean }
      discover_public_circles: {
        Args: { search?: string }
        Returns: {
          collective_target: number
          collective_unit: string
          created_at: string
          description: string
          end_date: string
          id: string
          join_rule: string
          member_count: number
          name: string
          timeframe_kind: string
          type: string
        }[]
      }
      esengo_has_product: { Args: { p_product: string }; Returns: boolean }
      in_focus_block: { Args: { p_block_id: string }; Returns: boolean }
      is_blocked: { Args: { other_id: string }; Returns: boolean }
      is_circle_member: { Args: { p_circle_id: string }; Returns: boolean }
      is_pact_member: { Args: { p_pact_id: string }; Returns: boolean }
      match_contact_keys: {
        Args: { p_emails: string[]; p_phone_hashes: string[] }
        Returns: {
          matched_email: string
          matched_phone_hash: string
          profile_id: string
        }[]
      }
      match_contacts: {
        Args: { p_emails: string[]; p_phone_hashes: string[] }
        Returns: string[]
      }
      my_circle_role: { Args: { p_circle_id: string }; Returns: string }
      owns_circle: { Args: { p_circle_id: string }; Returns: boolean }
      shares_circle_with: { Args: { other_id: string }; Returns: boolean }
      user_id: { Args: never; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
