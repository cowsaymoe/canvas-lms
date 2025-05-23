/*
 * Copyright (C) 2014 - present Instructure, Inc.
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

import {useScope as createI18nScope} from '@canvas/i18n'
import React from 'react'
import {bool, func, number, object} from 'prop-types'
import {Checkbox} from '@instructure/ui-checkbox'
import {ScreenReaderContent} from '@instructure/ui-a11y-content'

import EditExternalToolButton from './EditExternalToolButton'
import ManageUpdateExternalToolButton from './ManageUpdateExternalToolButton'
import ExternalToolPlacementButton from './ExternalToolPlacementButton'
import DeleteExternalToolButton from './DeleteExternalToolButton'
import DeploymentIdButton from './DeploymentIdButton'
import ConfigureExternalToolButton from './ConfigureExternalToolButton'
import ReregisterExternalToolButton from './ReregisterExternalToolButton'
import store from '../lib/ExternalAppsStore'
import classMunger from '../lib/classMunger'
import {showFlashAlert} from '@canvas/alerts/react/FlashAlert'
import '@canvas/jquery/jquery.instructure_misc_helpers'
import ExternalToolMigrationInfo from './ExternalToolMigrationInfo'

const I18n = createI18nScope('external_tools')

const MAX_FAVS = 2 // RCE and Top Navigation share this value
export default class ExternalToolsTableRow extends React.Component {
  static propTypes = {
    tool: object.isRequired,
    canAdd: bool.isRequired,
    canEdit: bool.isRequired,
    canDelete: bool.isRequired,
    setFocusAbove: func.isRequired,
    rceFavoriteCount: number.isRequired,
    topNavFavoriteCount: number.isRequired,
    showLTIFavoriteToggles: bool,
  }

  get is13Tool() {
    return this.props.tool.lti_version === '1.3'
  }

  nameClassNames = () => classMunger('external_tool', {muted: this.props.tool.enabled === false})

  disabledFlag = () => {
    if (this.props.tool.enabled === false) {
      return I18n.t('(disabled)')
    }
  }

  locked = () => {
    if (!this.props.tool.installed_locally) {
      return (
        <span className="text-muted">
          <i
            className="icon-lock"
            data-tooltip="top"
            title={I18n.t('%{app} was installed by Admin and is locked', {
              app: this.props.tool.name,
            })}
          />
        </span>
      )
    } else if (this.props.tool.is_master_course_child_content) {
      if (this.props.tool.restricted_by_master_course) {
        return (
          <span className="master-course-cell">
            <i
              className="icon-blueprint-lock"
              data-tooltip="top"
              title={I18n.t('%{app} was installed by the master course and is locked', {
                app: this.props.tool.name,
              })}
            />
          </span>
        )
      } else {
        return (
          <span className="master-course-cell">
            <i
              className="icon-blueprint"
              data-tooltip="top"
              title={I18n.t('%{app} was installed by the master course', {
                app: this.props.tool.name,
              })}
            />
          </span>
        )
      }
    }
  }

  returnFocus = (opts = {}) => {
    if (opts.passFocusUp) {
      this.props.setFocusAbove()
    } else {
      this.focus()
    }
  }

  focus() {
    if (this.button) {
      this.button.focus()
    }
  }

  handleFavoriteChange = type => event => {
    const checked = event.target.checked
    this.changeFavoriteLTI(checked, type)
  }

  changeFavoriteLTI = (checked, type) => {
    const success = _res => {
      const externalTools = store.getState().externalTools
      const tool = externalTools.find(t => t.app_id === this.props.tool.app_id)
      switch (type) {
        case 'top_nav':
          tool.is_top_nav_favorite = checked
          break
        case 'rce':
          tool.is_rce_favorite = checked
          break
      }
      store.setState({externalTools})
    }

    const error = err => {
      showFlashAlert({
        message: I18n.t('We were unable to update the app.'),
        err,
        type: 'error',
      })
    }

    store.setAsFavorite(this.props.tool, checked, type, success, error)
  }

  updateTool = tool => {
    const externalTools = store.getState().externalTools
    const toolRef = externalTools.find(t => String(t.app_id) === tool.id)
    if (toolRef) {
      toolRef.editor_button_settings = tool.editor_button
      store.setState({externalTools})
    }
  }

  validateTool = (r, placement) => {
    if (placement === 'editor_button') {
      if (r && !r.editor_button.enabled && this.props.tool.is_rce_favorite) {
        this.changeFavoriteLTI(false)
      }
      store.fetchWithDetails(this.props.tool).then(data => {
        this.updateTool(data)
      })
    }
  }

  renderButtons = () => {
    const permsToRenderSettingsCog = this.props.canEdit || this.props.canDelete
    const {tool} = this.props
    if (tool.installed_locally && !tool.restricted_by_master_course && permsToRenderSettingsCog) {
      let configureButton = null
      let updateBadge = null

      if (tool.tool_configuration) {
        configureButton = <ConfigureExternalToolButton tool={tool} returnFocus={this.returnFocus} />
      }

      if (tool.has_update) {
        const badgeAriaLabel = I18n.t('An update is available for %{toolName}', {
          toolName: tool.name,
        })
        updateBadge = <i className="icon-upload tool-update-badge" aria-label={badgeAriaLabel} />
      }

      return (
        <td className="links text-right" nowrap="nowrap">
          {updateBadge}
          <div className="al-dropdown__container">
            <button
              className="al-trigger btn"
              type="button"
              ref={c => {
                this.button = c
              }}
            >
              <i className="icon-settings" />
              <i className="icon-mini-arrow-down" />
              <span className="screenreader-only">{`${tool.name} ${I18n.t('Settings')}`}</span>
            </button>
            {/* eslint-disable-next-line jsx-a11y/role-supports-aria-props */}
            <ul
              className="al-options"
              role="menu"
              tabIndex="0"
              aria-hidden="true"
              aria-expanded="false"
            >
              {configureButton}
              <ManageUpdateExternalToolButton tool={tool} returnFocus={this.returnFocus} />
              <EditExternalToolButton
                tool={tool}
                canEdit={this.props.canEdit && !this.is13Tool}
                returnFocus={this.returnFocus}
              />
              <ExternalToolPlacementButton
                tool={tool}
                returnFocus={this.returnFocus}
                onToggleSuccess={this.validateTool}
              />
              <ReregisterExternalToolButton
                tool={tool}
                canAdd={this.props.canAdd}
                returnFocus={this.returnFocus}
              />
              {this.is13Tool ? (
                <DeploymentIdButton tool={tool} returnFocus={this.returnFocus} />
              ) : null}
              <DeleteExternalToolButton
                tool={tool}
                canDelete={this.props.canDelete}
                returnFocus={this.returnFocus}
              />
            </ul>
          </div>
        </td>
      )
    } else {
      return (
        <td className="links text-right e-tool-table-data" nowrap="nowrap">
          <ExternalToolPlacementButton
            tool={tool}
            type="button"
            returnFocus={this.returnFocus}
            onToggleSuccess={this.validateTool}
          />
        </td>
      )
    }
  }

  render() {
    const {tool} = this.props
    const show_top_nav_toggles = !!ENV.FEATURES?.top_navigation_placement

    return (
      <tr className="ExternalToolsTableRow external_tool_item">
        <td className="e-tool-table-data center-text">{this.locked()}</td>
        <td
          nowrap="nowrap"
          className={`${this.nameClassNames()} e-tool-table-data`}
          title={tool.name}
        >
          <div style={{display: 'flex', alignItems: 'center'}}>
            {tool.name} {this.disabledFlag()}
            {tool.migration_running ? (
              <ExternalToolMigrationInfo tool={tool} />
            ) : null}
          </div>
        </td>
        {this.props.showLTIFavoriteToggles && show_top_nav_toggles && (
          <td>
            {canBeTopNavFavorite(tool) ? (
              <Checkbox
                variant="toggle"
                label={
                  <ScreenReaderContent>{I18n.t('Top Navigation Favorite')}</ScreenReaderContent>
                }
                value={tool.app_id}
                onChange={this.handleFavoriteChange('top_nav')}
                checked={tool.is_top_nav_favorite}
                disabled={!tool.is_top_nav_favorite && this.props.topNavFavoriteCount >= MAX_FAVS}
              />
            ) : (
              I18n.t('NA')
            )}
          </td>
        )}
        {this.props.showLTIFavoriteToggles && (
          <td>
            {canBeRCEFavorite(tool) ? (
              <Checkbox
                variant="toggle"
                label={<ScreenReaderContent>{I18n.t('RCE Favorite')}</ScreenReaderContent>}
                value={tool.app_id}
                onChange={this.handleFavoriteChange('rce')}
                checked={tool.is_rce_favorite}
                disabled={
                  !tool.is_rce_favorite &&
                  this.props.rceFavoriteCount >= MAX_FAVS &&
                  !INST.editorButtons?.find(b => b.id === tool.app_id)?.on_by_default
                }
              />
            ) : (
              I18n.t('NA')
            )}
          </td>
        )}
        {this.renderButtons()}
      </tr>
    )
  }
}

// tool.is_rce_favorite only exists on the tool if
// it can be an RCE favorite
// see lib/lti/app_collator.rb#external_tool_definition
function canBeRCEFavorite(tool) {
  return (
    'is_rce_favorite' in tool && tool.editor_button_settings && tool.editor_button_settings.enabled
  )
}
// Similarly, tool.is_top_nav_favorite only exists
// on the tool if it can be a top nav favorite
// see lib/lti/app_collator.rb#external_tool_definition
function canBeTopNavFavorite(tool) {
  return (
    'is_top_nav_favorite' in tool &&
    tool.top_navigation_settings &&
    tool.top_navigation_settings.enabled
  )
}
