/*
 * Copyright (C) 2024 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

export type Product = {
  id: string
  global_product_id: string
  name: string
  company: Company
  logo_url: string
  tagline: string
  description: string
  updated_at: string
  canvas_lti_configurations: Lti[]
  privacy_and_security_badges: Badges[]
  accessibility_badges: Badges[]
  integration_badges: Badges[]
  screenshots: string[]
  terms_of_service_url: string
  privacy_policy_url: string
  accessibility_url: string
  support_url: string
  tags: Tag[]
  integration_resources: IntegrationResources
}

export type ToolStatus = {
  id: number
  name: string
  description: string
  color: string
}

export type OrganizationProduct = Product & {
  organization_tool: {
    privacy_status: ToolStatus
    product_status: ToolStatus
  }
}

export type Company = {
  id: number
  name: string
  company_url: string
}

export type Lti = {
  id: number
  integration_type: string
  description: string
  lti_placements: string[]
  lti_services: string[]
  url?: string
  global_inherited_key?: string
  configuration?: string
  unified_tool_id: string
}

export type Badges = {
  name: string
  image_url: string
  link: string
  description: string
}

export type TagGroup = {
  id: string
  name: string
  description: string
}

export type Tag = {
  id: string
  name: string
}

export type IntegrationResources = {
  comments: string | null
  resources: IntegrationResource[] | []
}

export type IntegrationResource = {
  name: string
  description: string
  content: string
}

export type ToolsByDisplayGroup = Array<{
  tag_group: TagGroup
  tools: Array<Product>
}>
